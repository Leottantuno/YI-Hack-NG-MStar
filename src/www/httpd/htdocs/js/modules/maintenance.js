var APP = APP || {};

APP.maintenance = (function($) {

    var timeoutVar;

    function init() {
        registerEventHandler();
        setRebootStatus("Camera is online.");
        getFwStatus();
        loadNetInfo();
    }

    function registerEventHandler() {
        $(document).on("click", '#button-save', function(e) {
            saveConfig();
        });
        $(document).on("click", '#button-load', function(e) {
            loadConfig();
        });
        $(document).on("click", '#button-reboot', function(e) {
            rebootCamera();
        });
        $(document).on("click", '#button-reset', function(e) {
            resetCamera();
        });
        $(document).on("click", '#button-upgrade', function(e) {
            upgradeFirmware();
        });
        $(document).on("change", '#fw-file', function(e) {
            onFwFileSelected();
        });
        $(document).on("click", '#button-upload-fw', function(e) {
            uploadFirmware();
        });
        $(document).on("click", '#button-umount', function(e) {
            umountSD();
        });
        $(document).on("click", '#btn-run-ping', function(e) {
            e.preventDefault();
            runPing();
        });
        $(document).on("click", '.btn-quick-ping', function(e) {
            e.preventDefault();
            var target = $(this).data('target');
            runPing(target);
        });
        $(document).on("keypress", '#ping-target', function(e) {
            if (e.which === 13) {
                e.preventDefault();
                runPing();
            }
        });
    }

    function saveConfig() {
        $('#button-save').attr("disabled", true);
        var xhr = new XMLHttpRequest();
        xhr.open('GET', 'cgi-bin/save.sh', true);
        xhr.responseType = 'blob';
        xhr.onload = function(e) {
            if (xhr.status == 200) {
                var myBlob = xhr.response;
                var url = URL.createObjectURL(myBlob);
                var $a = $('<a />', {
                    'href': url,
                    'download': 'config.7z',
                    'text': "click"
                }).hide().appendTo("body")[0].click();
                URL.revokeObjectURL(url);
            }
        };
        xhr.send();
    }

    function loadConfig() {
        $('#button-load').attr("disabled", true);
        var fileSelect = document.getElementById('button-file');
        var files = fileSelect.files;
        var formData = new FormData();

        for (var i = 0; i < files.length; i++) {
            var file = files[i];
            formData.append('files[]', file, file.name);
        }

        var xhr = new XMLHttpRequest();
        xhr.open('POST', 'cgi-bin/load.sh', true);
        xhr.onload = function() {
            if (xhr.status === 200) {
                $('#button-load').attr("disabled", false);
            }
            var myText = xhr.response;
            $('#text-load').text(myText);
        };
        xhr.send(formData);
    }

    function rebootCamera() {
        var confirmation = confirm("Are you sure you want to reboot?");
        if (confirmation) {
            $('#button-reboot').attr("disabled", true);
            $.ajax({
                type: "GET",
                url: 'cgi-bin/reboot.sh',
                dataType: "json",
                error: function(response) {
                    console.log('error', response);
                    $('#button-reboot').attr("disabled", false);
                },
                success: function(data) {
                    setRebootStatus("Camera is rebooting.");
                    waitForBoot();
                },
                complete: function() {
                    $('#button-reboot').attr("disabled", false);
                }
            });
        }
    }

    function waitForBoot() {
        setInterval(function() {
            $.ajax({
                url: 'index.html',
                cache: false,
                success: function(data) {
                    setRebootStatus("Camera is back online, redirecting to home.");
                    $('#button-reboot').attr("disabled", false);
                    window.location.href = "index.html";
                },
                error: function(data) {
                    setRebootStatus("Waiting for the camera to come back online.");
                },
                timeout: 3000,
            });
        }, 5000);
    }

    function resetCamera() {
        var confirmation = confirm("Are you sure you want to reset?");
        if (confirmation) {
            $('#button-reset').attr("disabled", true);
            $.ajax({
                type: "GET",
                url: 'cgi-bin/reset.sh',
                dataType: "json",
                error: function(response) {
                    console.log('error', response);
                },
                success: function(data) {
                    setResetStatus("Reset completed, reboot your camera.");
                },
                complete: function() {
                    $('#button-reset').attr("disabled", false);
                }
            });
        }
    }

    function upgradeFirmware() {
        $('#button-upgrade').attr("disabled", true);
        setFwStatus("Firmware download in progress.");
        $.ajax({
            type: "GET",
            url: 'cgi-bin/fw_upgrade.sh?get=upgrade',
            error: function(response) {
                console.log('error', response);
            },
            success: function(response) {
                setFwStatus(response);
                waitForUpgrade();
            },
            complete: function () {
                $('#button-upgrade').attr("disabled", false);
            }
        });
    }

    function onFwFileSelected() {
        var fileInput = document.getElementById('fw-file');
        var button = $('#button-upload-fw');
        var statusDiv = $('#fw-upload-status');
        if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
            button.prop('disabled', true);
            statusDiv.hide().text('');
            return;
        }
        var file = fileInput.files[0];
        var sizeMB = (file.size / (1024 * 1024)).toFixed(1);
        statusDiv.css('color', 'var(--text-muted)').text('Selected: ' + file.name + ' (' + sizeMB + ' MB)').show();
        button.prop('disabled', false);
    }

    function uploadFirmware() {
        var fileInput = document.getElementById('fw-file');
        if (!fileInput || !fileInput.files || fileInput.files.length === 0) return;
        var file = fileInput.files[0];
        if (!confirm("Are you sure you want to upload and install " + file.name + "?\nThe camera will reboot and flash the new firmware.")) {
            return;
        }

        $('#button-upload-fw').prop('disabled', true);
        $('#button-upgrade').prop('disabled', true);
        $('#fw-file').prop('disabled', true);
        $('#fw-upload-progress-container').show();
        $('#fw-upload-progress-bar').css('width', '0%');
        $('#fw-upload-progress-text').text('0%');

        var statusDiv = $('#fw-upload-status');
        statusDiv.css('color', 'var(--primary)').text('Starting upload...').show();

        var xhr = new XMLHttpRequest();
        xhr.open('POST', 'cgi-bin/fw_upload.sh', true);
        xhr.setRequestHeader('Content-Type', 'application/octet-stream');

        xhr.upload.onprogress = function(e) {
            if (e.lengthComputable) {
                var percent = Math.round((e.loaded / e.total) * 100);
                var loadedMB = (e.loaded / (1024 * 1024)).toFixed(1);
                var totalMB = (e.total / (1024 * 1024)).toFixed(1);
                $('#fw-upload-progress-bar').css('width', percent + '%');
                $('#fw-upload-progress-text').text(percent + '% (' + loadedMB + ' MB / ' + totalMB + ' MB)');
                if (percent >= 100) {
                    statusDiv.css('color', 'var(--primary)').text('Upload complete. Verifying archive & preparing upgrade...');
                } else {
                    statusDiv.css('color', 'var(--text-muted)').text('Uploading: ' + percent + '%');
                }
            }
        };

        xhr.onload = function() {
            var res;
            try {
                res = JSON.parse(xhr.responseText);
            } catch(e) {
                res = { error: xhr.status !== 200, message: xhr.responseText || 'Server error' };
            }

            if (xhr.status === 200 && !res.error) {
                $('#fw-upload-progress-bar').css('width', '100%');
                $('#fw-upload-progress-text').text('100%');
                statusDiv.css('color', '#10b981').text(res.message || 'Upgrade initiated! Rebooting camera...');
                waitForUpgrade();
            } else {
                statusDiv.css('color', '#ef4444').text('Error: ' + (res.message || 'Upload failed'));
                $('#button-upload-fw').prop('disabled', false);
                $('#button-upgrade').prop('disabled', false);
                $('#fw-file').prop('disabled', false);
                $('#fw-upload-progress-container').hide();
            }
        };

        xhr.onerror = function() {
            statusDiv.css('color', '#ef4444').text('Network error during firmware upload.');
            $('#button-upload-fw').prop('disabled', false);
            $('#button-upgrade').prop('disabled', false);
            $('#fw-file').prop('disabled', false);
            $('#fw-upload-progress-container').hide();
        };

        xhr.send(file);
    }

    function waitForUpgrade() {
        setInterval(function() {
            $.ajax({
                url: 'index.html',
                cache: false,
                success: function(data) {
                    setFwStatus("Camera is upgrading.");
                    $('#fw-upload-status').css('color', '#10b981').text("Camera is back online!");
                    $('#button-upgrade').attr("disabled", false);
                    window.location.href = "index.html";
                },
                error: function(data) {
                    setFwStatus("Waiting for the camera to come back online...");
                    $('#fw-upload-status').css('color', 'var(--primary)').text("Waiting for the camera to reboot and come back online...");
                },
                timeout: 3000,
            });
        }, 5000);
    }

    function setRebootStatus(text) {
        $('input[type="text"][data-key="STATUS"]').prop('value', text);
    }

    function setResetStatus(text) {
        $('input[type="text"][data-key="RESET"]').prop('value', text);
    }

    function setFwStatus(text) {
        $('input[type="text"][data-key="FW"]').prop('value', text);
    }

    function getFwStatus() {
        $.ajax({
            type: "GET",
            url: 'cgi-bin/fw_upgrade.sh?get=info',
            dataType: "json",
            error: function(response) {
                console.log('error', response);
                setFwStatus("Error getting fw info");
            },
            success: function(data) {
                if (data.local_fw) {
                    setFwStatus("Installed: " + data.fw_version + " - Available: local SD");
                } else {
                    setFwStatus("Installed: " + data.fw_version + " - Available: " + data.latest_fw);
                }
                var cleanFw = data.fw_version ? data.fw_version.replace(/^v/, '') : '';
                var cleanLatest = data.latest_fw ? data.latest_fw.replace(/^v/, '') : '';
                if ((cleanFw === cleanLatest) && (!data.local_fw)) {
                    $('#button-upgrade').attr("disabled", true);
                }
            }
        });
    }

    function umountSD() {
        $('#button-umount').attr("disabled", true);
        $('input[type="text"][data-key="SD"]').prop('value', "Umount SD in progress...");
        $.ajax({
            type: "GET",
            url: 'cgi-bin/umount_sd.sh',
            error: function(response) {
                console.log('error', response);
                $('#button-umount').attr("disabled", false);
                $('input[type="text"][data-key="SD"]').prop('value', "Failed");
            },
            success: function(response) {
                $('#button-umount').attr("disabled", false);
                if (response.error == "false") {
                    $('input[type="text"][data-key="SD"]').prop('value', "Success, reboot the cam.");
                } else {
                    console.log('error', response);
                    $('input[type="text"][data-key="SD"]').prop('value', "Failed");
                }
            }
        });
    }

    var currentGateway = "192.168.2.1";

    function loadNetInfo() {
        $.ajax({
            type: "GET",
            url: "cgi-bin/diag.sh?action=netinfo",
            dataType: "json",
            success: function(data) {
                if (data.error === "false") {
                    $('#diag-ssid').text(data.ssid || "Connected");
                    var sigText = data.signal_level ? data.signal_level + " dBm" : "-";
                    if (data.link_quality) sigText += " (Quality: " + data.link_quality + "/70)";
                    $('#diag-signal').text(sigText);
                    $('#diag-bssid').text(data.bssid || "-");
                    $('#diag-ip').text((data.ip || "-") + " / " + (data.netmask || "-"));
                    $('#diag-gw').text(data.gateway || "-");
                    $('#diag-dns').text(data.dns || "-");
                    $('#diag-mac').text(data.mac || "-");
                    if (data.gateway) {
                        currentGateway = data.gateway;
                        $('#ping-target').attr('placeholder', data.gateway);
                        if (!$('#ping-target').val()) {
                            $('#ping-target').val(data.gateway);
                        }
                    }
                }
            },
            error: function(err) {
                console.log("Error loading net info", err);
            }
        });
    }

    function runPing(target) {
        if (!target) target = $('#ping-target').val() || currentGateway;
        target = target.trim();
        if (target === "gw") target = currentGateway;
        $('#ping-target').val(target);

        var outElem = $('#ping-output');
        outElem.text("Pinging " + target + " (3 packets, timeout 2s)...");
        $('#btn-run-ping').attr('disabled', true);

        $.ajax({
            type: "GET",
            url: "cgi-bin/diag.sh?action=ping&target=" + encodeURIComponent(target),
            dataType: "json",
            success: function(res) {
                $('#btn-run-ping').attr('disabled', false);
                if (res.error === "false") {
                    var summary = "--- " + res.target + " ---\n";
                    if (res.loss) summary += "Loss: " + res.loss + "\n";
                    if (res.rtt) summary += "RTT: " + res.rtt + "\n\n";
                    outElem.text(summary + res.output);
                } else {
                    outElem.text("Ping error: " + (res.message || "Failed"));
                }
            },
            error: function(err) {
                $('#btn-run-ping').attr('disabled', false);
                outElem.text("Network error calling ping tool.");
                console.log("Ping error", err);
            }
        });
    }

    return {
        init: init
    };

})(jQuery);