.pragma library

function formatResetTime(isoString) {
    if (!isoString) return "--";
    var d = new Date(isoString);
    var now = new Date();
    var diffMs = d.getTime() - now.getTime();
    if (diffMs <= 0) return "now";

    var mins = Math.floor(diffMs / 60000);
    var hrs = Math.floor(mins / 60);
    mins = mins % 60;

    if (hrs > 0) return hrs + "h " + mins + "m";
    return mins + "m";
}

function formatResetTimeVerbose(isoString) {
    if (!isoString) return "N/A";
    var d = new Date(isoString);
    var now = new Date();
    var diffMs = d.getTime() - now.getTime();
    if (diffMs <= 0) return "Resetting now";

    var totalMins = Math.floor(diffMs / 60000);
    var hrs = Math.floor(totalMins / 60);
    var mins = totalMins % 60;

    if (hrs > 0) return "Resets in " + hrs + "h " + mins + "m";
    return "Resets in " + mins + "m";
}

function formatResetDateTime(isoString) {
    if (!isoString) return "N/A";
    var d = new Date(isoString);
    var now = new Date();
    if (d.getTime() <= now.getTime()) return "Resetting now";

    var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    var day = d.getDate();
    var month = d.getMonth() + 1;
    var dayStr = day < 10 ? "0" + day : "" + day;
    var monthStr = month < 10 ? "0" + month : "" + month;
    var hrs = d.getHours();
    var mins = d.getMinutes();
    var hrsStr = hrs < 10 ? "0" + hrs : "" + hrs;
    var minStr = mins < 10 ? "0" + mins : "" + mins;

    return "Resets " + days[d.getDay()] + ", " + dayStr + "." + monthStr +
           " at " + hrsStr + ":" + minStr;
}

function utilizationColor(pct, theme) {
    if (pct >= 80) return theme.error;
    if (pct >= 50) return theme.warning;
    return theme.primary;
}

function planLabel(subscriptionType) {
    switch (subscriptionType) {
    case "max": return "Max";
    case "pro": return "Pro";
    case "team": return "Team";
    case "enterprise": return "Enterprise";
    default: return subscriptionType || "Unknown";
    }
}

function tierLabel(tier) {
    if (!tier) return "";
    // "default_claude_max_5x" -> "Max 5x"
    var m = tier.match(/claude_(\w+)_(\d+x)/);
    if (m) return m[1].charAt(0).toUpperCase() + m[1].slice(1) + " " + m[2];
    return tier.replace(/_/g, " ");
}
