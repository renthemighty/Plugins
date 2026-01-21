/**
 * Admin JavaScript for WooCommerce Simple Bundle
 */

(function($) {
    'use strict';
    
    if (typeof wcsbAdmin === 'undefined') {
        console.error('WooCommerce Simple Bundle: wcsbAdmin is not defined');
        return;
    }
    
    $(document).ready(function() {
        
        // Show/hide bundle tab and pricing fields based on product type
        function toggleBundleFields() {
            var productType = $('select#product-type').val();
            
            if (productType === 'bundle') {
                $('.show_if_bundle').show();
                $('.hide_if_bundle').hide();
                
                // Force show pricing fields for bundles
                $('.product_data_tabs .general_tab').show();
                $('.general_options').show();
                $('.options_group.pricing').show();
                $('.pricing').show();
                $('._regular_price_field').show();
                $('._sale_price_field').show();
                $('._tax_status_field').parent().show();
                $('._tax_class_field').parent().show();
                
                // Show inventory and shipping tabs
                $('.inventory_tab').show();
                $('.shipping_tab').show();
            }
        }
        
        // Trigger on page load and on change
        $('select#product-type').on('change', toggleBundleFields).trigger('change');
        
        // Also trigger when clicking the General tab
        $('.general_tab a').on('click', function() {
            setTimeout(toggleBundleFields, 100);
        });
        
        // Product search autocomplete
        if ($.fn.autocomplete) {
            $('#wcsb_product_search').autocomplete({
                minLength: 3,
                source: function(request, response) {
                    $.ajax({
                        url: wcsbAdmin.ajax_url,
                        dataType: 'json',
                        data: {
                            action: 'wcsb_search_products',
                            security: wcsbAdmin.search_nonce,
                            term: request.term
                        },
                        success: function(data) {
                            response(data);
                        },
                        error: function(xhr, status, error) {
                            console.error('WooCommerce Simple Bundle: Search error - ' + error);
                            response([]);
                        }
                    });
                },
                select: function(event, ui) {
                    event.preventDefault();
                    
                    var productId = ui.item.id;
                    var productName = ui.item.text;
                    
                    // Check if product already exists
                    if ($('input[name="bundle_product_id[]"][value="' + productId + '"]').length) {
                        alert('This product is already in the bundle.');
                        $('#wcsb_product_search').val('');
                        return false;
                    }
                    
                    // Add product to bundle
                    var row = '<tr class="wcsb-bundle-item">' +
                        '<td class="sort"><span class="dashicons dashicons-menu"></span></td>' +
                        '<td class="product">' + productName + '<input type="hidden" name="bundle_product_id[]" value="' + productId + '" /></td>' +
                        '<td class="quantity"><input type="number" name="bundle_product_qty[]" value="1" min="1" step="1" class="small-text" /></td>' +
                        '<td class="remove"><button type="button" class="button wcsb-remove-item">Remove</button></td>' +
                        '</tr>';
                    
                    $('#wcsb_bundle_items').append(row);
                    $('#wcsb_product_search').val('');
                    
                    return false;
                }
            });
        } else {
            console.error('WooCommerce Simple Bundle: jQuery UI Autocomplete is not available');
        }
        
        // Remove bundle item
        $(document).on('click', '.wcsb-remove-item', function(e) {
            e.preventDefault();
            $(this).closest('tr').remove();
        });
        
        // Make bundle items sortable
        if ($.fn.sortable) {
            $('#wcsb_bundle_items').sortable({
                items: 'tr',
                cursor: 'move',
                axis: 'y',
                handle: '.sort',
                scrollSensitivity: 40
            });
        }
    });
    
})(jQuery);
