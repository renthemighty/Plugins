<?php
/**
 * Plugin Name: SPVS Cost Data Backup Export
 * Description: Export all SPVS cost data to CSV. Find it under WooCommerce menu.
 * Version: 1.0.3
 * Author: Megatron
 * License: GPL-2.0+
 */

if ( ! defined( 'ABSPATH' ) ) exit;

add_action( 'admin_menu', 'spvs_backup_add_menu', 99 );
add_action( 'admin_post_spvs_backup_export', 'spvs_backup_export_costs' );

function spvs_backup_add_menu() {
    add_submenu_page(
        'woocommerce',
        'Export Cost Data',
        '📥 Export Cost Data',
        'manage_woocommerce',
        'spvs-export-backup',
        'spvs_backup_render_page'
    );
}

function spvs_backup_render_page() {
    $export_url = wp_nonce_url( admin_url( 'admin-post.php?action=spvs_backup_export' ), 'spvs_backup_export' );
    ?>
    <div class="wrap">
        <h1>Export SPVS Cost Data</h1>

        <div class="card" style="max-width: 600px; margin-top: 20px;">
            <h2>Download Your Cost Data Backup</h2>
            <p>This will export all product costs to CSV.</p>
            <p>Format: <code>product_id, sku, cost</code></p>

            <p style="margin: 30px 0;">
                <a href="<?php echo esc_url( $export_url ); ?>" class="button button-primary button-hero">
                    📥 Download Cost Data CSV
                </a>
            </p>

            <p><strong>After downloading:</strong></p>
            <ol>
                <li>Save the CSV file</li>
                <li>Deactivate and delete this plugin</li>
                <li>Install new SPVS plugin v2.0.0</li>
                <li>Import the CSV to restore your costs</li>
            </ol>
        </div>
    </div>
    <?php
}

function spvs_backup_export_costs() {
    check_admin_referer( 'spvs_backup_export' );

    if ( ! current_user_can( 'manage_woocommerce' ) ) {
        wp_die( 'Access denied' );
    }

    $products = get_posts( array(
        'post_type'      => array( 'product', 'product_variation' ),
        'post_status'    => 'publish',
        'posts_per_page' => -1,
        'fields'         => 'ids',
    ) );

    header( 'Content-Type: text/csv; charset=utf-8' );
    header( 'Content-Disposition: attachment; filename="spvs-costs-backup-' . date( 'Y-m-d-His' ) . '.csv"' );

    $output = fopen( 'php://output', 'w' );
    fputcsv( $output, array( 'product_id', 'sku', 'cost' ) );

    foreach ( $products as $product_id ) {
        $product = wc_get_product( $product_id );
        if ( ! $product ) continue;

        $cost = get_post_meta( $product_id, '_spvs_cost_price', true );
        if ( $cost === '' || $cost === null ) continue;

        fputcsv( $output, array(
            $product_id,
            $product->get_sku() ?: '',
            $cost,
        ) );
    }

    fclose( $output );
    exit;
}
