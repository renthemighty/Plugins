jQuery(document).ready(function($) {
    let totalRecalculated = 0;
    let dateRange = { start: '', end: '' };

    // Start recalculation when button is clicked
    $(document).on('click', '#spvs-recalc-orders-btn', function(e) {
        e.preventDefault();

        // Get date range from button data attributes
        dateRange.start = $(this).data('start-date');
        dateRange.end = $(this).data('end-date');

        if (!confirm('Recalculate profit for orders from ' + dateRange.start + ' to ' + dateRange.end + '?\n\nThis will update orders in this date range using current cost data.')) {
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
        console.log('Starting recalc batch at offset:', offset, 'Date range:', dateRange);

        $.ajax({
            url: spvsRecalcOrders.ajaxurl,
            type: 'POST',
            timeout: 60000, // 60 second timeout
            data: {
                action: 'spvs_recalc_orders_batch',
                nonce: spvsRecalcOrders.nonce,
                offset: offset,
                start_date: dateRange.start,
                end_date: dateRange.end
            },
            success: function(response) {
                console.log('AJAX response:', response);
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
                    console.error('Recalc error:', response);
                    var errorMsg = response.data && response.data.message ? response.data.message : 'Unknown error';
                    $('#spvs-recalc-progress-status').html('<strong style="color: #d63638;">❌ Error: ' + errorMsg + '</strong>');
                    $('#spvs-recalc-complete-btn').fadeIn();
                }
            },
            error: function(xhr, status, error) {
                console.error('AJAX error:', status, error, xhr.responseText);
                var errorMsg = 'Network error';
                if (status === 'timeout') {
                    errorMsg = 'Request timed out - server might be busy';
                } else if (xhr.responseText) {
                    errorMsg = 'Server error: ' + xhr.status;
                }
                $('#spvs-recalc-progress-status').html('<strong style="color: #d63638;">❌ ' + errorMsg + '</strong>');
                $('#spvs-recalc-complete-btn').fadeIn();
            }
        });
    }

    // Reload page when complete button is clicked
    $(document).on('click', '#spvs-recalc-complete-btn', function() {
        // Preserve date range parameters when reloading
        var urlParams = new URLSearchParams(window.location.search);
        var startDate = urlParams.get('start_date') || '';
        var endDate = urlParams.get('end_date') || '';

        var reloadUrl = window.location.href.split('?')[0] + '?page=spvs-profit-reports';
        if (startDate) reloadUrl += '&start_date=' + encodeURIComponent(startDate);
        if (endDate) reloadUrl += '&end_date=' + encodeURIComponent(endDate);
        reloadUrl += '&spvs_recalc_done=' + totalRecalculated;

        window.location.href = reloadUrl;
    });
});
