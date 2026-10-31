var APP = APP || {};

function getUrlVar(key) {
    var hash;
    var hashes = window.location.href.slice(window.location.href.indexOf('?') + 1).split('&');
    for (var i = 0; i < hashes.length; i++) {
        hash = hashes[i].split('=');
        if (hash[0] == key)
            return hash[1];
    }
    return '';
}

APP.eventsfile = (function($) {

    function init() {
        updateEventsFilePage();
        registerEventHandler();
    }

    function registerEventHandler() {
        $(document).off('.eventsfile');

        $(document).on("click.eventsfile", '.button-delete', function(e) {
            e.preventDefault();
            var file = $(this).data('file') || $(this).attr('id').substring(14);
            if (!confirm('Are you sure you want to delete this recorded clip?')) return;
            deleteFile(file);
        });

        $(document).on("click.eventsfile", '.button-play', function(e) {
            e.preventDefault();
            var src = $(this).data('src') || $(this).attr('id').substring(12);
            playFile(src);
        });

        $(document).on("click.eventsfile", '.btn-speed', function(e) {
            e.preventDefault();
            var speed = parseFloat($(this).data('speed')) || 1;
            var vid = document.getElementById('video');
            if (vid) vid.playbackRate = speed;
            $('.btn-speed').removeClass('button-primary');
            $(this).addClass('button-primary');
        });

        $(document).on("click.eventsfile", '#btn-close-player', function(e) {
            e.preventDefault();
            var vid = document.getElementById('video');
            if (vid) {
                vid.pause();
                vid.src = '';
            }
            $('#player-container').hide();
        });
    }

    function deleteFile(filePath) {
        $.ajax({
            type: "GET",
            url: 'cgi-bin/eventsfiledel.sh?file=' + encodeURIComponent(filePath),
            dataType: "json",
            success: function(response) {
                updateEventsFilePage();
            },
            error: function(response) {
                console.log('error', response);
                updateEventsFilePage();
            }
        });
    }

    function playFile(src) {
        var videoPlayer = $('#video');
        var vid = videoPlayer[0];
        videoPlayer.attr('src', src);
        $('#btn-download-video').attr('href', src);
        $('#player-container').show();
        $('.btn-speed').removeClass('button-primary');
        $('.btn-speed[data-speed="1"]').addClass('button-primary');
        if (vid) {
            vid.playbackRate = 1;
            vid.play().catch(function() {});
        }
        $('html, body').animate({ scrollTop: $('#player-container').offset().top - 20 }, 200);
    }

    function updateEventsFilePage() {
        var dirname = getUrlVar('dirname');
        if (!dirname) return;

        $('#loading-status').text('Loading...').show();

        $.ajax({
            type: "GET",
            url: 'cgi-bin/eventsfile.sh?dirname=' + encodeURIComponent(dirname),
            dataType: "json",
            success: function(data) {
                $('#loading-status').fadeOut(300);
                document.getElementById("title-container").innerHTML = (data.date || dirname) + " - Select Event Clip";
                var html = "<table class=\"u-full-width padded-table\"><thead><tr>";
                html += "<th style=\"width:15%;\">Time</th>";
                html += "<th style=\"width:25%;\">Thumbnail</th>";
                html += "<th>File Name</th>";
                html += "<th style=\"width:160px;text-align:right;\">Actions</th>";
                html += "</tr></thead><tbody>";

                if (!data.records || data.records.length == 0) {
                    html += "<tr><td colspan=\"4\" style=\"text-align:center;padding:24px;color:var(--text-muted);\">No recorded events found in this folder</td></tr>";
                } else {
                    for (var i = 0; i < data.records.length; i++) {
                        var record = data.records[i];
                        var videoPath = "record/" + dirname + "/" + record.filename;
                        var deletePath = dirname + "/" + record.filename;

                        html += "<tr>";
                        html += "<td style=\"vertical-align:middle;font-weight:600;\">" + record.time + "</td>";
                        if (record.thumbfilename && record.thumbfilename !== "") {
                            var thumbPath = "record/" + dirname + "/" + record.thumbfilename;
                            html += "<td style=\"vertical-align:middle;\"><a href=\"" + videoPath + "\" class=\"button-play\" data-src=\"" + videoPath + "\">";
                            html += "<img src=\"" + thumbPath + "\" style=\"max-width:120px;border-radius:6px;box-shadow:0 2px 4px rgba(0,0,0,0.2);cursor:pointer;\" alt=\"thumb\" /></a></td>";
                        } else {
                            html += "<td style=\"vertical-align:middle;color:var(--text-muted);font-size:1.1rem;\">No thumbnail</td>";
                        }
                        html += "<td style=\"vertical-align:middle;\"><a href=\"" + videoPath + "\" target=\"_blank\">" + record.filename + "</a></td>";
                        html += "<td style=\"vertical-align:middle;text-align:right;\">";
                        html += "<button class=\"button button-primary btn-sm button-play\" data-src=\"" + videoPath + "\" style=\"margin-bottom:4px;margin-right:6px;\">Play</button>";
                        html += "<button class=\"button btn-sm button-delete\" data-file=\"" + deletePath + "\" style=\"margin-bottom:4px;color:#ef4444;\">Delete</button>";
                        html += "</td>";
                        html += "</tr>";
                    }
                }
                html += "</tbody></table>";
                document.getElementById("table-container").innerHTML = html;
            },
            error: function(response) {
                $('#loading-status').text('Error loading events').show();
                console.log('error', response);
            }
        });
    }

    return {
        init: init
    };

})(jQuery);
