var APP = APP || {};

APP.status = (function($) {

    var timeoutVar;
    var wifiStrength;

    function init() {
        updateLinks();
        updateStatusPage();
    }

    function updateLinks() {
        $.ajax({
            type: "GET",
            url: 'cgi-bin/links.sh',
            dataType: "json",
            success: function(data) {
                for (let key in data) {
                    var aTag = $('<a>', {
                        href: data[key]
                    });
                    aTag.text(data[key]);
                    $('#td_' + key).text('').append(aTag);
                    $('#tr_' + key).show();
                }
            },
            error: function(response) {
                console.log('error', response);
            }
        });
    }

    function updateStatusPage() {
        $.ajax({
            type: "GET",
            url: 'cgi-bin/status.json',
            dataType: "json",
            success: function(data) {
                for (let key in data) {
                    if (key != "wlan_essid" && key != "uptime" && key != "total_memory" && key != "free_memory" && key != "wlan_strength" && key != "load_avg" && key != "local_ip") {
                        $('#' + key).text(data[key]);
                    }
                }

                $('#local_ip').html('<div style="display:flex;justify-content:space-between;align-items:center;"><span>' + data.local_ip + '</span><input class="button btn-sm" type="button" value="Edit" onclick="window.location.href=\'?page=static_ip\'"/></div>');
                $('#wlan_essid').html('<div style="display:flex;justify-content:space-between;align-items:center;"><span>' + data.wlan_essid + '</span><input class="button btn-sm" type="button" value="Edit" onclick="window.location.href=\'?page=wifi\'"/></div>');
                $('#uptime').text(String.format("%t", parseInt(data.uptime)));

                if (data.load_avg) {
                    var parts = data.load_avg.trim().split(/\s+/);
                    if (parts.length >= 3) {
                        var l1 = parseFloat(parts[0]);
                        var l5 = parseFloat(parts[1]);
                        var l15 = parseFloat(parts[2]);
                        var statusTag = '';
                        if (l1 < 1.0) {
                            statusTag = '<span class="badge" style="background:rgba(34,197,94,0.15);color:#16a34a;margin-left:4px;">Normal</span>';
                        } else if (l1 < 3.5) {
                            statusTag = '<span class="badge" style="background:rgba(234,179,8,0.15);color:#ca8a04;margin-left:4px;">Active</span>';
                        } else {
                            statusTag = '<span class="badge" style="background:rgba(239,68,68,0.15);color:#dc2626;margin-left:4px;">Busy</span>';
                        }
                        $('#load_avg').html(
                            '<div style="display:flex;align-items:center;flex-wrap:wrap;gap:4px;">' +
                            '<span class="badge" title="1 min average tasks in CPU queue">1m: ' + l1.toFixed(2) + '</span>' +
                            '<span class="badge" title="5 min average tasks in CPU queue">5m: ' + l5.toFixed(2) + '</span>' +
                            '<span class="badge" title="15 min average tasks in CPU queue">15m: ' + l15.toFixed(2) + '</span>' +
                            statusTag +
                            '</div>'
                        );
                    } else {
                        $('#load_avg').text(data.load_avg);
                    }
                }

                if (data.free_memory && data.total_memory) {
                    var freeMb = (parseInt(data.free_memory) / 1024).toFixed(1);
                    var totalMb = (parseInt(data.total_memory) / 1024).toFixed(1);
                    var freePct = Math.round((parseInt(data.free_memory) / parseInt(data.total_memory)) * 100);
                    $('#memory').html(freeMb + ' / ' + totalMb + ' MB <span class="badge" style="margin-left:6px;">' + freePct + '% free</span>');
                } else {
                    $('#memory').text("" + data.free_memory + "/" + data.total_memory + " KB");
                }
                wifiStrength = parseInt(data.wlan_strength);
                if (wifiStrength >= 80) {
                    $('#wlan_strength').attr("src", "img/wlan_strong_signal.png")
                    $('#wlan_strength_percent').text(" " + wifiStrength.toString() + " %")
                } else if (wifiStrength >= 40 && wifiStrength < 80) {
                    $('#wlan_strength').attr("src", "img/wlan_medium_signal.png")
                    $('#wlan_strength_percent').text(" " + wifiStrength.toString() + " %")
                } else if (wifiStrength >= 0 && wifiStrength < 40) {
                    $('#wlan_strength').attr("src", "img/wlan_weak_signal.png")
                    $('#wlan_strength_percent').text(" " + wifiStrength.toString() + " %")
                } else {
                    $('#wlan_strength').attr("src", "img/wlan_no_signal.png")
                    $('#wlan_strength_percent').text(" No signal")
                }
            },
            error: function(response) {
                console.log('error', response);
            },
            complete: function() {
                clearTimeout(timeoutVar);
                timeoutVar = setTimeout(updateStatusPage, 10000);

            }
        });
    }

    return {
        init: init
    };

})(jQuery);