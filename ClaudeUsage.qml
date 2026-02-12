import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "UsageUtils.js" as Utils

PluginComponent {
    id: root
    layerNamespacePlugin: "claude-usage"
    popoutWidth: 360
    popoutHeight: 520

    // === Settings ===
    property int refreshIntervalMinutes: parseInt(pluginData.refreshInterval) || 2
    property string displayMode: pluginData.displayMode || "5h"
    property bool showFiveHour: pluginData.showFiveHour !== false
    property bool showSevenDay: pluginData.showSevenDay !== false
    property bool showOpus: pluginData.showOpus !== false
    property bool showSonnet: pluginData.showSonnet !== false
    property bool showExtraUsage: pluginData.showExtraUsage !== false
    property bool showPlanInfo: pluginData.showPlanInfo !== false

    readonly property string credentialsPath: (Quickshell.env("HOME") || Qt.getenv("HOME")) + "/.claude/.credentials.json"

    // === Credentials state ===
    property string accessToken: ""
    property string refreshToken: ""
    property real expiresAt: 0
    property string subscriptionType: ""
    property string rateLimitTier: ""

    // === Usage data ===
    property bool dataAvailable: false
    property string errorMessage: ""
    property bool loading: false
    property int _refreshRetries: 0
    readonly property int _maxRefreshRetries: 5
    property bool _savingCredentials: false

    property real fiveHourUtil: 0
    property string fiveHourReset: ""
    property real sevenDayUtil: 0
    property string sevenDayReset: ""
    property real sevenDayOpusUtil: 0
    property string sevenDayOpusReset: ""
    property real sevenDaySonnetUtil: 0
    property string sevenDaySonnetReset: ""

    property bool extraUsageEnabled: false
    property real extraUsageLimit: 0
    property real extraUsageUsed: 0
    property real extraUsageUtil: 0

    // === Pill helpers ===
    readonly property real _pillPct: {
        root._tick;
        var util = displayMode === "7d" ? sevenDayUtil : fiveHourUtil;
        var reset = displayMode === "7d" ? sevenDayReset : fiveHourReset;
        return Utils.effectiveUtilization(util, reset);
    }
    readonly property color _pillColor: dataAvailable ? Utils.utilizationColor(_pillPct, Theme) : Theme.surfaceVariantText
    readonly property string _pillReset: displayMode === "7d" ? sevenDayReset : fiveHourReset

    // === Tick timer (forces re-eval of reset time bindings) ===
    property int _tick: 0
    property bool _resetDetected: false
    Timer {
        interval: 30000
        running: root.dataAvailable
        repeat: true
        onTriggered: {
            root._tick++;
            if (root.dataAvailable && !root._resetDetected) {
                var now = Date.now();
                var resets = [root.fiveHourReset, root.sevenDayReset, root.sevenDayOpusReset, root.sevenDaySonnetReset];
                for (var i = 0; i < resets.length; i++) {
                    if (resets[i] && new Date(resets[i]).getTime() <= now) {
                        root._resetDetected = true;
                        root.loadUsage();
                        break;
                    }
                }
            }
        }
    }

    // === Error helper ===
    function setError(msg) {
        errorMessage = msg;
        dataAvailable = false;
        loading = false;
    }

    // === Refresh retry timer ===
    Timer {
        id: refreshRetryTimer
        interval: 30000
        running: false
        repeat: false
        onTriggered: root.loadUsage()
    }

    function scheduleRetry() {
        if (_refreshRetries < _maxRefreshRetries) {
            _refreshRetries++;
            console.warn("[claudeUsage] Scheduling retry " + _refreshRetries + "/" + _maxRefreshRetries + " in 30s");
            refreshRetryTimer.restart();
        }
    }

    // === Credential loading (watches file for external changes) ===
    FileView {
        id: credentialsFile
        path: root.credentialsPath
        watchChanges: true

        onLoaded: {
            var content = credentialsFile.text();
            if (!content) {
                root.setError("No credentials file found\nRun 'claude' to log in");
                return;
            }

            try {
                var oauth = JSON.parse(content).claudeAiOauth;
                if (!oauth) {
                    root.setError("No OAuth credentials found");
                    return;
                }

                root.accessToken = oauth.accessToken || "";
                root.refreshToken = oauth.refreshToken || "";
                root.expiresAt = oauth.expiresAt || 0;
                root.subscriptionType = oauth.subscriptionType || "";
                root.rateLimitTier = oauth.rateLimitTier || "";

                if (root.expiresAt > 0 && Date.now() > root.expiresAt)
                    root.refreshOAuthToken();
                else
                    root.fetchUsage();
            } catch (e) {
                root.setError("Failed to parse credentials");
            }
        }

        onFileChanged: {
            if (root._savingCredentials) {
                root._savingCredentials = false;
                return;
            }
            root.loading = true;
            credentialsFile.reload();
        }

        onLoadFailed: {
            root.setError("No credentials file found\nRun 'claude' to log in");
        }
    }

    // === Token refresh ===
    Process {
        id: tokenRefresher
        property string output: ""

        stdout: SplitParser {
            onRead: line => { tokenRefresher.output += line; }
        }

        onExited: (exitCode) => {
            if (exitCode !== 0 || !output) {
                console.warn("[claudeUsage] Token refresh failed: exitCode=" + exitCode + " output=" + (output || "(empty)"));
                root.setError("Token refresh failed\nRetrying...");
                root.scheduleRetry();
                output = "";
                return;
            }

            try {
                var resp = JSON.parse(output);
                if (resp.error) {
                    console.warn("[claudeUsage] Token refresh error: " + resp.error + " - " + (resp.error_description || ""));
                    root.setError("Token refresh failed\n" + (resp.error_description || "Retrying..."));
                    root.scheduleRetry();
                    output = "";
                    return;
                }
                if (!resp.access_token) {
                    console.warn("[claudeUsage] Token refresh: no access_token in response");
                    root.setError("Token refresh failed\nRetrying...");
                    root.scheduleRetry();
                    output = "";
                    return;
                }

                root._refreshRetries = 0;
                root.accessToken = resp.access_token;
                root.refreshToken = resp.refresh_token || root.refreshToken;
                root.expiresAt = Date.now() + (resp.expires_in * 1000);
                root.saveCredentials();
                root.fetchUsage();
            } catch (e) {
                console.warn("[claudeUsage] Token refresh parse error: " + e + " raw=" + output.substring(0, 200));
                root.setError("Token refresh failed\nRetrying...");
                root.scheduleRetry();
            }
            output = "";
        }
    }

    function refreshOAuthToken() {
        if (!refreshToken) {
            setError("No refresh token available\nRun 'claude' to log in");
            return;
        }
        if (tokenRefresher.running) return;

        tokenRefresher.output = "";
        tokenRefresher.command = [
            "curl", "-sS", "--connect-timeout", "10", "--max-time", "15",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify({
                grant_type: "refresh_token",
                client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
                refresh_token: refreshToken
            }),
            "https://console.anthropic.com/v1/oauth/token"
        ];
        tokenRefresher.running = true;
    }

    // === Save refreshed credentials ===
    Process {
        id: credSaver
        property string jsonData: ""
        command: ["tee", root.credentialsPath]
        stdinEnabled: true
        onStarted: { write(jsonData + "\n"); stdinClose(); }
    }

    function saveCredentials() {
        _savingCredentials = true;
        credSaver.jsonData = JSON.stringify({
            claudeAiOauth: {
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                scopes: ["user:inference", "user:mcp_servers", "user:profile", "user:sessions:claude_code"],
                subscriptionType: subscriptionType,
                rateLimitTier: rateLimitTier
            }
        });
        credSaver.running = true;
    }

    // === Usage API ===
    Process {
        id: usageFetcher
        property string output: ""

        stdout: SplitParser {
            onRead: line => { usageFetcher.output += line; }
        }

        onExited: (exitCode) => {
            root.loading = false;

            // Extract HTTP status code appended by curl -w
            var idx = output.lastIndexOf("HTTP_STATUS:");
            var httpCode = idx >= 0 ? parseInt(output.substring(idx + 12)) : 0;
            var body = idx >= 0 ? output.substring(0, idx) : output;
            output = "";

            if (exitCode !== 0 || !body) {
                console.warn("[claudeUsage] Usage fetch failed: exitCode=" + exitCode);
                root.setError("Failed to fetch usage data\nRetrying...");
                root.scheduleRetry();
                return;
            }

            if (httpCode === 401) {
                console.warn("[claudeUsage] Usage fetch got 401, refreshing token");
                root.refreshOAuthToken();
                return;
            }

            try {
                var resp = JSON.parse(body);
                root._refreshRetries = 0;
                root.applyUsageData(resp);
            } catch (e) {
                console.warn("[claudeUsage] Usage parse error: " + e + " raw=" + body.substring(0, 200));
                root.setError("Failed to parse usage data\nRetrying...");
                root.scheduleRetry();
            }
        }
    }

    function applyUsageData(resp) {
        function extract(obj) {
            return obj ? { util: obj.utilization || 0, reset: obj.resets_at || "" }
                       : { util: 0, reset: "" };
        }

        var fh = extract(resp.five_hour);
        fiveHourUtil = fh.util;
        fiveHourReset = fh.reset;

        var sd = extract(resp.seven_day);
        sevenDayUtil = sd.util;
        sevenDayReset = sd.reset;

        var opus = extract(resp.seven_day_opus);
        sevenDayOpusUtil = opus.util;
        sevenDayOpusReset = opus.reset;

        var sonnet = extract(resp.seven_day_sonnet);
        sevenDaySonnetUtil = sonnet.util;
        sevenDaySonnetReset = sonnet.reset;

        if (resp.extra_usage) {
            extraUsageEnabled = resp.extra_usage.is_enabled || false;
            extraUsageLimit = resp.extra_usage.monthly_limit || 0;
            extraUsageUsed = resp.extra_usage.used_credits || 0;
            extraUsageUtil = resp.extra_usage.utilization || 0;
        } else {
            extraUsageEnabled = false;
        }

        dataAvailable = true;
        errorMessage = "";
        _resetDetected = false;
    }

    function fetchUsage() {
        if (!accessToken) {
            setError("No access token");
            return;
        }
        if (usageFetcher.running) return;

        usageFetcher.output = "";
        usageFetcher.command = [
            "curl", "-sS", "--connect-timeout", "10", "--max-time", "15",
            "-w", "\nHTTP_STATUS:%{http_code}",
            "-H", "Accept: application/json",
            "-H", "Authorization: Bearer " + accessToken,
            "-H", "anthropic-beta: oauth-2025-04-20",
            "-H", "User-Agent: claude-code/2.0.32",
            "https://api.anthropic.com/api/oauth/usage"
        ];
        usageFetcher.running = true;
    }

    function loadUsage() {
        loading = true;
        credentialsFile.reload();
    }

    Timer {
        id: refreshTimer
        interval: root.refreshIntervalMinutes * 60 * 1000
        running: true
        repeat: true
        onTriggered: { root._refreshRetries = 0; root.loadUsage(); }
    }

    Component.onCompleted: root.loadUsage()

    // === Widget properties ===
    ccWidgetIcon: "smart_toy"
    ccWidgetPrimaryText: "Claude Usage"
    ccWidgetSecondaryText: {
        if (!dataAvailable) return errorMessage || "Loading...";
        root._tick;
        return Math.round(Utils.effectiveUtilization(fiveHourUtil, fiveHourReset)) + "% (5h) \u2022 "
             + Math.round(Utils.effectiveUtilization(sevenDayUtil, sevenDayReset)) + "% (7d)";
    }
    ccWidgetIsActive: dataAvailable

    // === Bar pills ===
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "smart_toy"
                size: root.iconSize
                color: root._pillColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.dataAvailable ? Math.round(root._pillPct) + "%" : "--"
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                font.weight: Font.Bold
                color: root._pillColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                visible: root.dataAvailable
                width: 1
                height: root.iconSize
                color: Theme.outline
                opacity: 0.3
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.dataAvailable
                text: { root._tick; return Utils.formatResetTime(root._pillReset); }
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            DankIcon {
                name: "smart_toy"
                size: root.iconSize
                color: root._pillColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.dataAvailable ? Math.round(root._pillPct) + "%" : "--"
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                font.weight: Font.Bold
                color: root._pillColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // === Popout ===
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Claude " + Utils.planLabel(root.subscriptionType)
            detailsText: {
                if (!root.dataAvailable) return root.errorMessage || "Loading...";
                var tier = Utils.tierLabel(root.rateLimitTier);
                return tier || "Plan usage";
            }
            showCloseButton: false

            headerActions: Component {
                Row {
                    spacing: 4

                    DankActionButton {
                        iconName: "refresh"
                        iconColor: root.loading ? Theme.primary : Theme.surfaceVariantText
                        buttonSize: 28
                        tooltipText: "Refresh"
                        tooltipSide: "bottom"
                        onClicked: root.loadUsage()

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 800
                            loops: Animation.Infinite
                            running: root.loading
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Error state
                StyledRect {
                    visible: !root.dataAvailable
                    width: parent.width
                    height: errorCol.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.1)

                    Column {
                        id: errorCol
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingL * 2
                        spacing: Theme.spacingM

                        DankIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "cloud_off"
                            size: 40
                            color: Theme.error
                            opacity: 0.6
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                text: "Unable to load usage"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.error
                                horizontalAlignment: Text.AlignHCenter
                            }

                            StyledText {
                                width: parent.width
                                text: root.errorMessage || "Check your credentials"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                // Usage cards
                UsageCard {
                    visible: root.dataAvailable && root.showFiveHour
                    iconName: "schedule"
                    title: "5-Hour Window"
                    subtitle: { root._tick; return Utils.formatResetTimeVerbose(root.fiveHourReset); }
                    utilization: { root._tick; return Utils.effectiveUtilization(root.fiveHourUtil, root.fiveHourReset); }
                }

                UsageCard {
                    visible: root.dataAvailable && root.showSevenDay
                    iconName: "date_range"
                    title: "Weekly Window"
                    subtitle: { root._tick; return Utils.formatResetDateTime(root.sevenDayReset); }
                    utilization: { root._tick; return Utils.effectiveUtilization(root.sevenDayUtil, root.sevenDayReset); }
                }

                UsageCard {
                    visible: root.dataAvailable && root.showOpus && root.sevenDayOpusUtil > 0
                    iconName: "auto_awesome"
                    title: "Weekly Opus"
                    subtitle: { root._tick; return Utils.formatResetDateTime(root.sevenDayOpusReset); }
                    utilization: { root._tick; return Utils.effectiveUtilization(root.sevenDayOpusUtil, root.sevenDayOpusReset); }
                }

                UsageCard {
                    visible: root.dataAvailable && root.showSonnet && root.sevenDaySonnetUtil > 0
                    iconName: "bolt"
                    title: "Weekly Sonnet"
                    subtitle: { root._tick; return Utils.formatResetDateTime(root.sevenDaySonnetReset); }
                    utilization: { root._tick; return Utils.effectiveUtilization(root.sevenDaySonnetUtil, root.sevenDaySonnetReset); }
                }

                UsageCard {
                    visible: root.dataAvailable && root.showExtraUsage && root.extraUsageEnabled
                    iconName: "payments"
                    title: "Extra Usage"
                    subtitle: "$" + root.extraUsageUsed.toFixed(2) + " / $" + root.extraUsageLimit.toFixed(2)
                    utilization: root.extraUsageUtil
                }

                // Plan info
                StyledRect {
                    visible: root.dataAvailable && root.showPlanInfo
                    width: parent.width
                    height: planContent.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)

                    Row {
                        id: planContent
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "verified"
                            size: 18
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: "Claude " + Utils.planLabel(root.subscriptionType)
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                visible: root.rateLimitTier !== ""
                                text: Utils.tierLabel(root.rateLimitTier)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }
        }
    }

    // === Reusable components ===

    component UsageCard: StyledRect {
        property string iconName
        property string title
        property string subtitle
        property real utilization: 0

        readonly property color barColor: Utils.utilizationColor(utilization, Theme)

        width: parent.width
        height: cardCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: cardCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Item {
                width: parent.width
                implicitHeight: titleCol.implicitHeight

                Row {
                    anchors.left: parent.left
                    anchors.right: pctText.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    DankIcon {
                        name: iconName
                        size: 20
                        color: barColor
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.8
                    }

                    Column {
                        id: titleCol
                        spacing: 2

                        StyledText {
                            text: title
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: subtitle
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                StyledText {
                    id: pctText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(utilization) + "%"
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    color: barColor
                }
            }

            UsageBar {
                width: parent.width
                utilization: parent.parent.utilization
                barColor: parent.parent.barColor
            }
        }
    }

    component UsageBar: Item {
        property real utilization: 0
        property color barColor: Utils.utilizationColor(utilization, Theme)
        height: 6

        StyledRect {
            anchors.fill: parent
            radius: 3
            color: Qt.rgba(barColor.r, barColor.g, barColor.b, 0.15)

            StyledRect {
                width: parent.width * Math.min(utilization, 100) / 100
                height: parent.height
                radius: 3
                color: barColor

                Behavior on width {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
