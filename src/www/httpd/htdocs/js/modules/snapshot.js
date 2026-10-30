var APP = APP || {};

APP.snapshot = (function($) {

    var isPlaying = true;
    var refreshTimer = null;
    var isFetching = false;
    var currentRes = 'high';
    var currentRate = 2000;
    var watermark = 'yes';
    var currentFrameUrl = '';

    function init() {
        if (refreshTimer) {
            clearTimeout(refreshTimer);
            refreshTimer = null;
        }
        isPlaying = true;
        isFetching = false;
        currentRes = $('#selectRes').val() || 'high';
        var rateVal = $('#selectRate').val();
        currentRate = rateVal === 'manual' ? 0 : (parseInt(rateVal, 10) || 2000);
        watermark = $('#selectWatermark').val() || 'yes';

        updateHudHostname();
        updateHudRes();
        registerEventHandler();
        fetchFrame();
    }

    function updateHudHostname() {
        var h = (typeof hostname !== 'undefined' && hostname) ? hostname : 'YI-CAM';
        $('#hudHostname').text(h);
    }

    function updateHudRes() {
        $('#hudRes').text(currentRes === 'high' ? '1080p' : '360p');
    }

    function registerEventHandler() {
        $(document).off('.snapshot');

        $(document).on('click.snapshot', '#btnToggleLive', function(e) {
            e.preventDefault();
            togglePlayPause();
        });

        $(document).on('click.snapshot', '#btnRefresh', function(e) {
            e.preventDefault();
            $('#snapSpinner').show();
            fetchFrame();
        });

        $(document).on('click.snapshot', '#btnDownload', function(e) {
            e.preventDefault();
            downloadSnapshot();
        });

        $(document).on('click.snapshot', '#btnFullscreen', function(e) {
            e.preventDefault();
            toggleFullscreen();
        });

        $(document).on('change.snapshot', '#selectRes', function(e) {
            currentRes = $(this).val();
            updateHudRes();
            $('#snapSpinner').show();
            fetchFrame();
        });

        $(document).on('change.snapshot', '#selectRate', function(e) {
            var val = $(this).val();
            if (val === 'manual') {
                currentRate = 0;
                setPlayingState(false);
            } else {
                currentRate = parseInt(val, 10) || 2000;
                if (!isPlaying) {
                    setPlayingState(true);
                } else {
                    scheduleNext(currentRate);
                }
            }
        });

        $(document).on('change.snapshot', '#selectWatermark', function(e) {
            watermark = $(this).val();
            $('#snapSpinner').show();
            fetchFrame();
        });
    }

    function fetchFrame() {
        var imgElement = document.getElementById('imgSnap');
        if (!imgElement) {
            if (refreshTimer) clearTimeout(refreshTimer);
            return;
        }

        if (isFetching) return;
        isFetching = true;

        var startTime = Date.now();
        var img = new Image();
        var url = 'cgi-bin/snapshot.sh?res=' + currentRes + '&watermark=' + watermark + '&t=' + startTime;

        img.onload = function() {
            var target = document.getElementById('imgSnap');
            if (!target) {
                isFetching = false;
                return;
            }
            target.src = img.src;
            currentFrameUrl = img.src;
            isFetching = false;
            $('#snapSpinner').hide();

            var elapsed = ((Date.now() - startTime) / 1000).toFixed(2);
            var now = new Date();
            var timeStr = now.toLocaleTimeString();
            $('#hudStatus').text('Frame: ' + timeStr + ' (' + elapsed + 's)');

            if (isPlaying && currentRate > 0) {
                scheduleNext(currentRate);
            }
        };

        img.onerror = function() {
            isFetching = false;
            $('#snapSpinner').hide();
            $('#hudStatus').text('Error loading frame');

            if (isPlaying && currentRate > 0) {
                scheduleNext(3000);
            }
        };

        img.src = url;
    }

    function scheduleNext(ms) {
        if (refreshTimer) clearTimeout(refreshTimer);
        refreshTimer = setTimeout(function() {
            fetchFrame();
        }, ms);
    }

    function setPlayingState(play) {
        isPlaying = play;
        if (refreshTimer) {
            clearTimeout(refreshTimer);
            refreshTimer = null;
        }

        if (isPlaying) {
            $('#btnToggleLive').text('Pause').addClass('button-primary');
            $('#liveBadge').css('background', '#10b981');
            $('#liveBadgeText').text('LIVE');
            $('#liveDot').addClass('live-pulse').css('opacity', '1');
            fetchFrame();
        } else {
            $('#btnToggleLive').text('Resume').removeClass('button-primary');
            $('#liveBadge').css('background', '#64748b');
            $('#liveBadgeText').text('PAUSED');
            $('#liveDot').removeClass('live-pulse').css('opacity', '0.5');
            $('#hudStatus').text('Paused');
        }
    }

    function togglePlayPause() {
        setPlayingState(!isPlaying);
    }

    function downloadSnapshot() {
        if (!currentFrameUrl) {
            var el = document.getElementById('imgSnap');
            if (el && el.src) currentFrameUrl = el.src;
        }
        if (!currentFrameUrl) return;

        var h = (typeof hostname !== 'undefined' && hostname) ? hostname : 'cam';
        var d = new Date();
        var dateStr = d.getFullYear() +
            ('0' + (d.getMonth() + 1)).slice(-2) +
            ('0' + d.getDate()).slice(-2) + '_' +
            ('0' + d.getHours()).slice(-2) +
            ('0' + d.getMinutes()).slice(-2) +
            ('0' + d.getSeconds()).slice(-2);
        var filename = 'snapshot_' + h + '_' + dateStr + '.jpg';

        var a = document.createElement('a');
        a.href = currentFrameUrl;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }

    function toggleFullscreen() {
        var container = document.getElementById('liveViewContainer');
        if (!container) return;

        if (!document.fullscreenElement && !document.webkitFullscreenElement) {
            if (container.requestFullscreen) {
                container.requestFullscreen();
            } else if (container.webkitRequestFullscreen) {
                container.webkitRequestFullscreen();
            }
        } else {
            if (document.exitFullscreen) {
                document.exitFullscreen();
            } else if (document.webkitExitFullscreen) {
                document.webkitExitFullscreen();
            }
        }
    }

    return {
        init: init
    };

})(jQuery);
