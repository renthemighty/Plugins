jQuery(document).ready(function($) {
    'use strict';

    var exportState = {
        isRunning: false,
        isCancelled: false,
        totalBatches: 0,
        currentBatch: 0
    };

    var $startButton = $('#wc-top-spenders-start-export');
    var $progressContainer = $('#wc-top-spenders-progress');
    var $progressFill = $('#wc-top-spenders-progress-fill');
    var $progressText = $('#wc-top-spenders-progress-text');
    var $cancelButton = $('#wc-top-spenders-cancel');
    var $completeContainer = $('#wc-top-spenders-complete');
    var $errorContainer = $('#wc-top-spenders-error');
    var $downloadButton = $('#wc-top-spenders-download');
    var $newExportButton = $('#wc-top-spenders-new-export');
    var $retryButton = $('#wc-top-spenders-retry');

    // Start export button
    $startButton.on('click', function() {
        if (exportState.isRunning) {
            return;
        }
        startExport();
    });

    // Cancel button
    $cancelButton.on('click', function() {
        if (!exportState.isRunning) {
            return;
        }
        cancelExport();
    });

    // Download button
    $downloadButton.on('click', function() {
        downloadCSV();
    });

    // New export button
    $newExportButton.on('click', function() {
        resetUI();
    });

    // Retry button
    $retryButton.on('click', function() {
        resetUI();
        startExport();
    });

    function startExport() {
        exportState.isRunning = true;
        exportState.isCancelled = false;
        exportState.currentBatch = 0;
        exportState.totalBatches = 0;

        // Hide other containers and show progress
        $startButton.hide();
        $completeContainer.hide();
        $errorContainer.hide();
        $progressContainer.show();

        updateProgress(0, wcTopSpenders.strings.starting);

        // Start export via AJAX
        $.ajax({
            url: wcTopSpenders.ajaxUrl,
            type: 'POST',
            data: {
                action: 'wc_top_spenders_start_export',
                nonce: wcTopSpenders.nonce
            },
            success: function(response) {
                if (response.success) {
                    exportState.totalBatches = response.data.total_batches;

                    // Start processing batches
                    processBatchSequence(0);
                } else {
                    showError(response.data.message || 'Unknown error occurred');
                }
            },
            error: function(xhr, status, error) {
                showError('Network error: ' + error);
            }
        });
    }

    function processBatchSequence(batchNumber) {
        if (exportState.isCancelled) {
            return;
        }

        if (batchNumber >= exportState.totalBatches) {
            // All batches complete
            onExportComplete();
            return;
        }

        exportState.currentBatch = batchNumber;

        // Update progress
        var percent = Math.round((batchNumber / exportState.totalBatches) * 100);
        var message = sprintf(
            wcTopSpenders.strings.processing,
            batchNumber + 1,
            exportState.totalBatches
        );
        updateProgress(percent, message);

        // Process this batch
        $.ajax({
            url: wcTopSpenders.ajaxUrl,
            type: 'POST',
            data: {
                action: 'wc_top_spenders_process_batch',
                nonce: wcTopSpenders.nonce,
                batch: batchNumber
            },
            success: function(response) {
                if (response.success) {
                    // Wait for rate limit before processing next batch
                    setTimeout(function() {
                        processBatchSequence(batchNumber + 1);
                    }, wcTopSpenders.rateLimitMs);
                } else {
                    showError(response.data.message || 'Error processing batch');
                }
            },
            error: function(xhr, status, error) {
                showError('Network error during batch processing: ' + error);
            }
        });
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
        exportState.isRunning = false;

        // Cancel on server
        $.ajax({
            url: wcTopSpenders.ajaxUrl,
            type: 'POST',
            data: {
                action: 'wc_top_spenders_cancel_export',
                nonce: wcTopSpenders.nonce
            }
        });

        updateProgress(0, wcTopSpenders.strings.cancelled);

        setTimeout(function() {
            resetUI();
        }, 1000);
    }

    function downloadCSV() {
        // Create a hidden form to download the CSV
        var form = $('<form>', {
            method: 'POST',
            action: wcTopSpenders.ajaxUrl
        });

        form.append($('<input>', {
            type: 'hidden',
            name: 'action',
            value: 'wc_top_spenders_download_csv'
        }));

        form.append($('<input>', {
            type: 'hidden',
            name: 'nonce',
            value: wcTopSpenders.nonce
        }));

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
        exportState.isRunning = false;
        exportState.isCancelled = false;
        exportState.currentBatch = 0;
        exportState.totalBatches = 0;

        $progressContainer.hide();
        $completeContainer.hide();
        $errorContainer.hide();
        $startButton.show();

        updateProgress(0, '');
    }

    // Simple sprintf implementation for string formatting
    function sprintf(str) {
        var args = Array.prototype.slice.call(arguments, 1);
        var i = 0;
        return str.replace(/%[sd]/g, function() {
            return args[i++];
        });
    }
});
