jQuery(document).ready(function($) {
    'use strict';

    var MAX_RETRIES    = 3;   // retries per batch before giving up
    var RETRY_DELAY_MS = 2000; // base delay; doubles on each retry

    var exportState = {
        isRunning:    false,
        isCancelled:  false,
        totalBatches: 0,
        currentBatch: 0
    };

    var $startButton       = $('#wc-top-spenders-start-export');
    var $progressContainer = $('#wc-top-spenders-progress');
    var $progressFill      = $('#wc-top-spenders-progress-fill');
    var $progressText      = $('#wc-top-spenders-progress-text');
    var $cancelButton      = $('#wc-top-spenders-cancel');
    var $completeContainer = $('#wc-top-spenders-complete');
    var $errorContainer    = $('#wc-top-spenders-error');
    var $downloadButton    = $('#wc-top-spenders-download');
    var $newExportButton   = $('#wc-top-spenders-new-export');
    var $retryButton       = $('#wc-top-spenders-retry');

    $startButton.on('click', function() {
        if (!exportState.isRunning) { startExport(); }
    });

    $cancelButton.on('click', function() {
        if (exportState.isRunning) { cancelExport(); }
    });

    $downloadButton.on('click', function() { downloadCSV(); });

    $newExportButton.on('click', function() { resetUI(); });

    $retryButton.on('click', function() {
        resetUI();
        startExport();
    });

    // -------------------------------------------------------------------------
    // Phase 1 — start: server runs the expensive sort query once and caches it.
    // Use a long timeout (5 min) to handle large stores.
    // -------------------------------------------------------------------------
    function startExport() {
        exportState.isRunning   = true;
        exportState.isCancelled = false;
        exportState.currentBatch  = 0;
        exportState.totalBatches  = 0;

        $startButton.hide();
        $completeContainer.hide();
        $errorContainer.hide();
        $progressContainer.show();

        updateProgress(0, 'Preparing user data\u2026');

        $.ajax({
            url:     wcTopSpenders.ajaxUrl,
            type:    'POST',
            timeout: 300000, // 5 minutes — server builds the sorted list here
            data: {
                action: 'wc_top_spenders_start_export',
                nonce:  wcTopSpenders.nonce
            },
            success: function(response) {
                if (response.success) {
                    exportState.totalBatches = response.data.total_batches;
                    processBatchSequence(0, 0);
                } else {
                    showError(response.data.message || 'Unknown error');
                }
            },
            error: function(xhr, status, error) {
                var msg = (status === 'timeout')
                    ? 'The server took too long to prepare the data. Try again or contact your host to increase PHP max_execution_time.'
                    : ('Network error: ' + error);
                showError(msg);
            }
        });
    }

    // -------------------------------------------------------------------------
    // Phase 2 — batches: cheap WHERE ID IN (...) lookups, retried on failure.
    // -------------------------------------------------------------------------
    function processBatchSequence(batchNumber, retryCount) {
        if (exportState.isCancelled) { return; }

        if (batchNumber >= exportState.totalBatches) {
            onExportComplete();
            return;
        }

        exportState.currentBatch = batchNumber;

        var percent = Math.round((batchNumber / exportState.totalBatches) * 100);
        var message = sprintf(
            wcTopSpenders.strings.processing,
            batchNumber + 1,
            exportState.totalBatches
        );
        if (retryCount > 0) {
            message += sprintf(' (retry %d/%d)', retryCount, MAX_RETRIES);
        }
        updateProgress(percent, message);

        $.ajax({
            url:     wcTopSpenders.ajaxUrl,
            type:    'POST',
            timeout: 60000, // 60 s per batch
            data: {
                action: 'wc_top_spenders_process_batch',
                nonce:  wcTopSpenders.nonce,
                batch:  batchNumber
            },
            success: function(response) {
                if (response.success) {
                    // Enforce 1 request per second between batches.
                    setTimeout(function() {
                        processBatchSequence(batchNumber + 1, 0);
                    }, wcTopSpenders.rateLimitMs);
                } else {
                    handleBatchError(
                        batchNumber, retryCount,
                        response.data.message || 'Server error processing batch'
                    );
                }
            },
            error: function(xhr, status, error) {
                var msg = (status === 'timeout')
                    ? 'Batch ' + (batchNumber + 1) + ' timed out.'
                    : ('Network error: ' + error);
                handleBatchError(batchNumber, retryCount, msg);
            }
        });
    }

    function handleBatchError(batchNumber, retryCount, errorMsg) {
        if (exportState.isCancelled) { return; }

        if (retryCount < MAX_RETRIES) {
            var delay = RETRY_DELAY_MS * Math.pow(2, retryCount); // 2s, 4s, 8s
            updateProgress(
                Math.round((batchNumber / exportState.totalBatches) * 100),
                sprintf('Retrying batch %d in %ds\u2026', batchNumber + 1, delay / 1000)
            );
            setTimeout(function() {
                processBatchSequence(batchNumber, retryCount + 1);
            }, delay);
        } else {
            showError(errorMsg + ' (failed after ' + MAX_RETRIES + ' retries)');
        }
    }

    function onExportComplete() {
        exportState.isRunning = false;
        updateProgress(100, wcTopSpenders.strings.complete);
        setTimeout(function() {
            $progressContainer.hide();
            $completeContainer.show();
        }, 500);
    }

    function cancelExport() {
        exportState.isCancelled = true;
        exportState.isRunning   = false;
        $.ajax({
            url:  wcTopSpenders.ajaxUrl,
            type: 'POST',
            data: { action: 'wc_top_spenders_cancel_export', nonce: wcTopSpenders.nonce }
        });
        updateProgress(0, wcTopSpenders.strings.cancelled);
        setTimeout(resetUI, 1000);
    }

    function downloadCSV() {
        var form = $('<form>', { method: 'POST', action: wcTopSpenders.ajaxUrl });
        form.append($('<input>', { type: 'hidden', name: 'action', value: 'wc_top_spenders_download_csv' }));
        form.append($('<input>', { type: 'hidden', name: 'nonce',  value: wcTopSpenders.nonce }));
        $('body').append(form);
        form.submit();
        form.remove();
    }

    function updateProgress(percent, message) {
        $progressFill.css('width', percent + '%');
        $progressText.text(message);
    }

    function showError(message) {
        exportState.isRunning = false;
        $progressContainer.hide();
        $errorContainer.show();
        $errorContainer.find('.wc-top-spenders-error').text(
            sprintf(wcTopSpenders.strings.error, message)
        );
    }

    function resetUI() {
        exportState.isRunning    = false;
        exportState.isCancelled  = false;
        exportState.currentBatch = 0;
        exportState.totalBatches = 0;
        $progressContainer.hide();
        $completeContainer.hide();
        $errorContainer.hide();
        $startButton.show();
        updateProgress(0, '');
    }

    function sprintf(str) {
        var args = Array.prototype.slice.call(arguments, 1);
        var i = 0;
        return str.replace(/%[sd]/g, function() { return args[i++]; });
    }
});
