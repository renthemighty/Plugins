jQuery(document).ready(function($) {
    let totalImported = 0;
    let totalUpdated = 0;
    let totalSkipped = 0;

    // Start import when button is clicked
    $(document).on('click', '#spvs-start-cog-import', function(e) {
        e.preventDefault();

        if (!confirm('Import cost data from WooCommerce Cost of Goods? A backup will be created first.')) {
            return;
        }

        // Show modal
        $('#spvs-import-modal').fadeIn();
        $('#spvs-import-complete-btn').hide();

        // Reset counters
        totalImported = 0;
        totalUpdated = 0;
        totalSkipped = 0;

        // Start batch processing
        processNextBatch(0);
    });

    function processNextBatch(offset) {
        $.ajax({
            url: spvsCogImport.ajaxurl,
            type: 'POST',
            data: {
                action: 'spvs_cog_import_batch',
                nonce: spvsCogImport.nonce,
                offset: offset
            },
            success: function(response) {
                if (response.success) {
                    const data = response.data;

                    // Accumulate totals
                    totalImported += data.imported;
                    totalUpdated += data.updated;
                    totalSkipped += data.skipped;

                    // Update progress bar
                    $('#spvs-progress-bar').css('width', data.percentage + '%');
                    $('#spvs-progress-bar').text(data.percentage + '%');

                    // Update status
                    $('#spvs-progress-status').text('Processing: ' + data.processed + ' of ' + data.total + ' products');

                    // Update details
                    $('#spvs-detail-imported').text(totalImported);
                    $('#spvs-detail-updated').text(totalUpdated);
                    $('#spvs-detail-skipped').text(totalSkipped);
                    $('#spvs-detail-processed').text(data.processed + ' / ' + data.total);

                    // Check if complete
                    if (data.complete) {
                        $('#spvs-progress-status').html('<strong style="color: #00a32a;">✅ Import Complete!</strong>');
                        $('#spvs-import-complete-btn').fadeIn();
                    } else {
                        // Process next batch after 1 second delay
                        setTimeout(function() {
                            processNextBatch(data.processed);
                        }, 1000);
                    }
                } else {
                    $('#spvs-progress-status').html('<strong style="color: #d63638;">❌ Error: ' + (response.data ? response.data.message : 'Unknown error') + '</strong>');
                    $('#spvs-import-complete-btn').fadeIn();
                }
            },
            error: function() {
                $('#spvs-progress-status').html('<strong style="color: #d63638;">❌ Network error occurred</strong>');
                $('#spvs-import-complete-btn').fadeIn();
            }
        });
    }

    // Reload page when complete button is clicked
    $(document).on('click', '#spvs-import-complete-btn', function() {
        window.location.href = window.location.href.split('?')[0] + '?page=spvs-inventory&spvs_msg=' + encodeURIComponent('cog_import_done:' + totalImported + ':' + totalUpdated + ':' + totalSkipped);
    });
});
