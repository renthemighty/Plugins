<?php
/**
 * Plugin Name: SPVS Cost Data Backup Export - Universal
 * Description: Export ALL product costs from any plugin (SPVS, WooCommerce Cost of Goods, etc). Find it under WooCommerce menu.
 * Version: 1.1.0
 * Author: Megatron
 * License: GPL-2.0+
 */

if ( ! defined( 'ABSPATH' ) ) exit;

add_action( 'admin_menu', 'spvs_backup_add_menu', 99 );
add_action( 'admin_post_spvs_backup_export_universal', 'spvs_backup_export_costs_universal' );

function spvs_backup_add_menu() {
    add_submenu_page(
        'woocommerce',
        'Export All Cost Data',
        '📥 Export All Costs',
        'manage_woocommerce',
        'spvs-export-backup-universal',
        'spvs_backup_render_page_universal'
    );
}

function spvs_backup_render_page_universal() {
    global $wpdb;

    // Search for all known cost meta keys
    $cost_meta_keys = array(
        '_spvs_cost_price'          => 'SPVS Plugin',
        '_wc_cog_cost'              => 'WooCommerce Cost of Goods',
        '_alg_wc_cog_cost'          => 'Cost of Goods for WooCommerce',
        '_wc_cost_of_good'          => 'WooCommerce Cost',
        '_cost'                     => 'Generic Cost',
        'cost'                      => 'Simple Cost',
        '_product_cost'             => 'Product Cost',
    );

    // Find which meta keys actually exist in the database
    $found_keys = array();
    foreach ( $cost_meta_keys as $key => $label ) {
        $count = $wpdb->get_var( $wpdb->prepare( "
            SELECT COUNT(DISTINCT post_id)
            FROM {$wpdb->postmeta}
            WHERE meta_key = %s
            AND meta_value != ''
            AND meta_value IS NOT NULL
        ", $key ) );

        if ( $count > 0 ) {
            $found_keys[ $key ] = array(
                'label' => $label,
                'count' => $count
            );
        }
    }

    $export_url = wp_nonce_url( admin_url( 'admin-post.php?action=spvs_backup_export_universal' ), 'spvs_backup_export_universal' );
    ?>
    <div class="wrap">
        <h1>Export All Product Costs - Universal Backup</h1>

        <div class="card" style="max-width: 700px; margin-top: 20px;">
            <h2>Found Cost Data</h2>

            <?php if ( ! empty( $found_keys ) ) : ?>
                <table class="widefat striped" style="margin: 15px 0;">
                    <thead>
                        <tr>
                            <th>Plugin/Source</th>
                            <th>Meta Key</th>
                            <th>Products</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ( $found_keys as $key => $data ) : ?>
                            <tr>
                                <td><strong><?php echo esc_html( $data['label'] ); ?></strong></td>
                                <td><code><?php echo esc_html( $key ); ?></code></td>
                                <td><?php echo (int) $data['count']; ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>

                <p><strong>Total: <?php echo array_sum( wp_list_pluck( $found_keys, 'count' ) ); ?> products with cost data</strong></p>

                <p style="margin: 30px 0;">
                    <a href="<?php echo esc_url( $export_url ); ?>" class="button button-primary button-hero">
                        📥 Download Complete Cost Backup (CSV)
                    </a>
                </p>

                <p class="description">
                    The CSV will include all costs found from any plugin, with separate columns for each source.
                </p>

            <?php else : ?>
                <p><strong>No cost data found in your database.</strong></p>
                <p>This plugin searches for costs from: SPVS, WooCommerce Cost of Goods, and other common plugins.</p>
            <?php endif; ?>

            <hr>
            <p><strong>After downloading:</strong></p>
            <ol>
                <li>Save the CSV file safely</li>
                <li>Deactivate and delete this plugin</li>
                <li>You can import this CSV into any cost plugin</li>
            </ol>
        </div>
    </div>
    <?php
}

function spvs_backup_export_costs_universal() {
    check_admin_referer( 'spvs_backup_export_universal' );

    if ( ! current_user_can( 'manage_woocommerce' ) ) {
        wp_die( 'Access denied' );
    }

    global $wpdb;

    // All known cost meta keys
    $cost_meta_keys = array(
        '_spvs_cost_price',
        '_wc_cog_cost',
        '_alg_wc_cog_cost',
        '_wc_cost_of_good',
        '_cost',
        'cost',
        '_product_cost',
    );

    // Get ALL products
    $products = get_posts( array(
        'post_type'      => array( 'product', 'product_variation' ),
        'post_status'    => 'publish',
        'posts_per_page' => -1,
        'fields'         => 'ids',
    ) );

    // Set CSV headers
    header( 'Content-Type: text/csv; charset=utf-8' );
    header( 'Content-Disposition: attachment; filename="all-costs-backup-' . date( 'Y-m-d-His' ) . '.csv"' );

    $output = fopen( 'php://output', 'w' );

    // Header row with all possible cost columns
    $header = array( 'product_id', 'sku', 'name', 'type' );
    foreach ( $cost_meta_keys as $key ) {
        $header[] = $key;
    }
    fputcsv( $output, $header );

    $exported = 0;

    foreach ( $products as $product_id ) {
        $product = wc_get_product( $product_id );

        $row = array(
            $product_id,
            $product ? $product->get_sku() : '',
            $product ? $product->get_name() : '',
            $product ? $product->get_type() : '',
        );

        $has_cost = false;

        // Get cost from each meta key
        foreach ( $cost_meta_keys as $key ) {
            $cost = get_post_meta( $product_id, $key, true );

            if ( $cost !== '' && $cost !== null && $cost != '0' ) {
                $has_cost = true;
            }

            $row[] = $cost !== '' ? $cost : '';
        }

        // Only export if at least one cost field has data
        if ( $has_cost ) {
            fputcsv( $output, $row );
            $exported++;
        }
    }

    fclose( $output );
    exit;
}
