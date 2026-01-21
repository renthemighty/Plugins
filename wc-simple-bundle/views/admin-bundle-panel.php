<?php
/**
 * Bundle Products Admin Panel
 *
 * @package WC_Simple_Bundle
 */

defined('ABSPATH') || exit;
?>

<div id="bundle_product_data" class="panel woocommerce_options_panel hidden">
    <div class="options_group">
        <p class="form-field">
            <label><?php esc_html_e('Search Products', 'wc-simple-bundle'); ?></label>
            <input type="text" id="wcsb_product_search" style="width: 50%;" 
                   placeholder="<?php esc_attr_e('Search for a product&hellip;', 'wc-simple-bundle'); ?>" />
        </p>
    </div>
    
    <div class="options_group">
        <div class="wcsb-bundle-products">
            <table class="widefat wcsb-bundle-table">
                <thead>
                    <tr>
                        <th class="sort"></th>
                        <th><?php esc_html_e('Product', 'wc-simple-bundle'); ?></th>
                        <th><?php esc_html_e('Quantity', 'wc-simple-bundle'); ?></th>
                        <th class="remove"></th>
                    </tr>
                </thead>
                <tbody id="wcsb_bundle_items">
                    <?php
                    if (!empty($bundle_data) && is_array($bundle_data)) {
                        foreach ($bundle_data as $index => $item) {
                            $bundled_product = wc_get_product($item['product_id']);
                            if (!$bundled_product) {
                                continue;
                            }
                            ?>
                            <tr class="wcsb-bundle-item">
                                <td class="sort">
                                    <span class="dashicons dashicons-menu"></span>
                                </td>
                                <td class="product">
                                    <?php echo esc_html($bundled_product->get_formatted_name()); ?>
                                    <input type="hidden" name="bundle_product_id[]" value="<?php echo esc_attr($item['product_id']); ?>" />
                                </td>
                                <td class="quantity">
                                    <input type="number" name="bundle_product_qty[]" 
                                           value="<?php echo esc_attr($item['quantity']); ?>" 
                                           min="1" step="1" class="small-text" />
                                </td>
                                <td class="remove">
                                    <button type="button" class="button wcsb-remove-item"><?php esc_html_e('Remove', 'wc-simple-bundle'); ?></button>
                                </td>
                            </tr>
                            <?php
                        }
                    }
                    ?>
                </tbody>
            </table>
        </div>
    </div>
</div>
