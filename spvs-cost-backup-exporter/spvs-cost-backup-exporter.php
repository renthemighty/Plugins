<?php
/**
 * Plugin Name: SPVS Cost Data Backup Export
 * Description: One-time use plugin to export all SPVS cost data to CSV. Deactivate and delete after use.
 * Version: 1.0.0
 * Author: Megatron
 * License: GPL-2.0+
 */

if ( ! defined( 'ABSPATH' ) ) exit;

class SPVS_Cost_Backup_Exporter {

    public function __construct() {
        add_action( 'admin_menu', array( $this, 'add_menu' ) );
        add_action( 'admin_post_spvs_backup_export', array( $this, 'export_costs' ) );
    }

    public function add_menu() {
        add_management_page(
            'SPVS Cost Backup',
            'SPVS Cost Backup',
            'manage_options',
            'spvs-cost-backup',
            array( $this, 'render_page' )
        );
    }

    public function render_page() {
        ?>
        <div class="wrap">
            <h1>SPVS Cost Data Backup</h1>

            <div class="notice notice-warning">
                <p><strong>One-Time Use Plugin</strong></p>
                <p>This plugin exports all your SPVS product cost data to CSV.</p>
                <p>After downloading your backup, deactivate and delete this plugin.</p>
            </div>

            <div class="card" style="max-width: 600px; margin-top: 20px;">
                <h2>Export Your Cost Data</h2>
                <p>Click the button below to download a CSV file containing all product costs from your database.</p>
                <p>The CSV will include: Product ID, SKU, Name, Type, and Cost</p>

                <form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
                    <input type="hidden" name="action" value="spvs_backup_export">
                    <?php wp_nonce_field( 'spvs_backup_export' ); ?>
                    <p>
                        <button type="submit" class="button button-primary button-hero">
                            📥 Download Cost Data Backup (CSV)
                        </button>
                    </p>
                </form>

                <hr>
                <h3>Next Steps:</h3>
                <ol>
                    <li>Click the button above to download your backup</li>
                    <li>Save the CSV file safely</li>
                    <li>Install and activate the new SPVS plugin (v2.0.0)</li>
                    <li>Import your costs using the CSV file</li>
                    <li>Deactivate and delete this backup plugin</li>
                </ol>
            </div>
        </div>
        <?php
    }

    public function export_costs() {
        check_admin_referer( 'spvs_backup_export' );

        if ( ! current_user_can( 'manage_options' ) ) {
            wp_die( 'Access denied' );
        }

        // Get all products and variations
        $args = array(
            'post_type'      => array( 'product', 'product_variation' ),
            'post_status'    => 'publish',
            'posts_per_page' => -1,
            'fields'         => 'ids',
        );

        $products = get_posts( $args );

        // Set CSV headers
        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename="spvs-costs-backup-' . date( 'Y-m-d-His' ) . '.csv"' );
        header( 'Pragma: no-cache' );
        header( 'Expires: 0' );

        $output = fopen( 'php://output', 'w' );

        // Header row
        fputcsv( $output, array( 'product_id', 'sku', 'name', 'type', 'cost' ) );

        $exported = 0;

        foreach ( $products as $product_id ) {
            $product = wc_get_product( $product_id );
            if ( ! $product ) continue;

            // Get cost (try common meta keys)
            $cost = get_post_meta( $product_id, '_spvs_cost_price', true );

            // Skip if no cost
            if ( $cost === '' || $cost === null ) continue;

            fputcsv( $output, array(
                $product_id,
                $product->get_sku() ?: '',
                $product->get_name(),
                $product->get_type(),
                $cost,
            ) );

            $exported++;
        }

        fclose( $output );
        exit;
    }
}

new SPVS_Cost_Backup_Exporter();
