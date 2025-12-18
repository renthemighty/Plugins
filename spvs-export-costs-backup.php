<?php
/**
 * SPVS Cost Data Export - Standalone Script
 *
 * Upload this file to your WordPress root directory and access it directly:
 * https://yoursite.com/spvs-export-costs-backup.php
 *
 * It will download a CSV file with all your product costs.
 * Delete this file after use for security.
 */

// Load WordPress
require_once( 'wp-load.php' );

// Security check
if ( ! current_user_can( 'manage_woocommerce' ) ) {
    die( 'Access denied. You must be logged in as an administrator.' );
}

// Get all products
$args = array(
    'post_type'      => array( 'product', 'product_variation' ),
    'post_status'    => 'publish',
    'posts_per_page' => -1,
    'fields'         => 'ids',
);

$products = get_posts( $args );

// Set headers for CSV download
header( 'Content-Type: text/csv; charset=utf-8' );
header( 'Content-Disposition: attachment; filename="spvs-costs-backup-' . date( 'Y-m-d-His' ) . '.csv"' );
header( 'Pragma: no-cache' );
header( 'Expires: 0' );

// Open output stream
$output = fopen( 'php://output', 'w' );

// Write header row
fputcsv( $output, array( 'product_id', 'sku', 'name', 'type', 'cost' ) );

// Export each product
foreach ( $products as $product_id ) {
    $product = wc_get_product( $product_id );
    if ( ! $product ) continue;

    // Get cost value (check both possible meta keys)
    $cost = get_post_meta( $product_id, '_spvs_cost_price', true );

    // Only export if cost exists
    if ( $cost === '' || $cost === null ) continue;

    fputcsv( $output, array(
        $product_id,
        $product->get_sku() ?: '',
        $product->get_name(),
        $product->get_type(),
        $cost,
    ) );
}

fclose( $output );
exit;
