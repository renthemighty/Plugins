<?php
/**
 * Plugin Name: SPVS Cost Data Backup Export
 * Description: One-time use plugin to export all SPVS cost data to CSV. Deactivate and delete after use.
 * Version: 1.0.2
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
        add_menu_page(
            'Export SPVS Costs',
            'Export SPVS Costs',
            'manage_options',
            'spvs-cost-backup',
            array( $this, 'render_page' ),
            'dashicons-download',
            30
        );
    }

    public function render_page() {
        $export_url = wp_nonce_url( admin_url( 'admin-post.php?action=spvs_backup_export' ), 'spvs_backup_export' );
        ?>
        <div class="wrap">
            <h1>Export SPVS Cost Data</h1>

            <div class="card" style="max-width: 600px; margin-top: 20px;">
                <h2>Download Your Cost Data Backup</h2>
                <p>Click the button below to download a CSV file containing all your product costs.</p>
                <p>Format: <code>product_id, sku, cost</code></p>

                <p style="margin: 30px 0;">
                    <a href="<?php echo esc_url( $export_url ); ?>" class="button button-primary button-hero">
                        📥 Download Cost Data (CSV)
                    </a>
                </p>

                <hr>
                <h3>After downloading:</h3>
                <ol>
                    <li>Save the CSV file safely</li>
                    <li>Deactivate and delete this plugin</li>
                    <li>Install the new SPVS plugin (v2.0.0)</li>
                    <li>Import your costs using the CSV</li>
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

        $args = array(
            'post_type'      => array( 'product', 'product_variation' ),
            'post_status'    => 'publish',
            'posts_per_page' => -1,
            'fields'         => 'ids',
        );

        $products = get_posts( $args );

        header( 'Content-Type: text/csv; charset=utf-8' );
        header( 'Content-Disposition: attachment; filename="spvs-costs-backup-' . date( 'Y-m-d-His' ) . '.csv"' );
        header( 'Pragma: no-cache' );
        header( 'Expires: 0' );

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
}

new SPVS_Cost_Backup_Exporter();
