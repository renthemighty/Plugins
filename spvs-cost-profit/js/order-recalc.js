jQuery(document).ready(function($) {
    let totalRecalculated = 0;

    // Start recalculation when button is clicked
    $(document).on('click', '#spvs-recalc-orders-btn', function(e) {
        e.preventDefault();

        if (!confirm('Recalculate profit for ALL historical orders using current cost data?\n\nThis will update all orders to reflect any cost changes made since they were originally placed.')) {
            return;
        }

        // Show modal
        $('#spvs-recalc-modal').fadeIn();
        $('#spvs-recalc-complete-btn').hide();

        // Reset counter
        totalRecalculated = 0;

        // Start batch processing
        processNextRecalcBatch(0);
    });

    function processNextRecalcBatch(offset) {
        $.ajax({
            url: spvsRecalcOrders.ajaxurl,
            type: 'POST',
            data: {
                action: 'spvs_recalc_orders_batch',
                nonce: spvsRecalcOrders.nonce,
                offset: offset
            },
            success: function(response) {
                if (response.success) {
                    const data = response.data;

                    // Accumulate totals
                    totalRecalculated += data.recalculated;

                    // Update progress bar
                    $('#spvs-recalc-progress-bar').css('width', data.percentage + '%');
                    $('#spvs-recalc-progress-bar').text(data.percentage + '%');

                    // Update status
                    $('#spvs-recalc-progress-status').text('Processing: ' + data.processed + ' of ' + data.total + ' orders');

                    // Update details
                    $('#spvs-recalc-detail-count').text(totalRecalculated);
                    $('#spvs-recalc-detail-processed').text(data.processed + ' / ' + data.total);

                    // Check if complete
                    if (data.complete) {
                        $('#spvs-recalc-progress-status').html('<strong style="color: #00a32a;">✅ Recalculation Complete!</strong>');
                        $('#spvs-recalc-complete-btn').fadeIn();
                    } else {
                        // Process next batch after 500ms delay
                        setTimeout(function() {
                            processNextRecalcBatch(data.processed);
                        }, 500);
                    }
                } else {
                    $('#spvs-recalc-progress-status').html('<strong style="color: #d63638;">❌ Error: ' + (response.data ? response.data.message : 'Unknown error') + '</strong>');
                    $('#spvs-recalc-complete-btn').fadeIn();
                }
            },
            error: function() {
                $('#spvs-recalc-progress-status').html('<strong style="color: #d63638;">❌ Network error occurred</strong>');
                $('#spvs-recalc-complete-btn').fadeIn();
            }
        });
    }

    // Reload page when complete button is clicked
    $(document).on('click', '#spvs-recalc-complete-btn', function() {
        window.location.href = window.location.href.split('?')[0] + '?page=spvs-profit-reports&spvs_recalc_done=' + totalRecalculated;
    });
});
