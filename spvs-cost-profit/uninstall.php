<?php
/**
 * Uninstall script for SPVS Cost & Profit for WooCommerce
 *
 * This file is executed when the plugin is uninstalled via WordPress admin.
 * It removes all plugin data from the database.
 *
 * @package SPVS_Cost_Profit
 */

// If uninstall not called from WordPress, exit
if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
    exit;
}

/**
 * Remove plugin data
 *
 * This function removes all data created by the plugin:
 * - Product meta (cost prices, cached totals)
 * - Order meta (profit calculations)
 * - Options
 * - Transients
 * - Scheduled events
 */
function spvs_cost_profit_uninstall() {
    global $wpdb;

    // Remove scheduled cron events
    $timestamp = wp_next_scheduled( 'spvs_daily_inventory_recalc' );
    if ( $timestamp ) {
        wp_unschedule_event( $timestamp, 'spvs_daily_inventory_recalc' );
    }

    // Remove transients
    delete_transient( 'spvs_inventory_recalc_lock' );
    delete_transient( 'spvs_cost_import_misses' );

    // Remove options
    delete_option( 'spvs_inventory_totals_cache' );
    delete_option( 'spvs_db_version' );
    delete_option( 'spvs_last_integrity_check' );

    // Remove audit table (v3.0.0+)
    $audit_table = $wpdb->prefix . 'spvs_cost_audit';
    $wpdb->query( "DROP TABLE IF EXISTS {$audit_table}" );

    // Remove product meta data
    $product_meta_keys = array(
        '_spvs_cost_price',
        '_spvs_stock_cost_total',
        '_spvs_stock_retail_total',
    );

    foreach ( $product_meta_keys as $meta_key ) {
        $wpdb->query(
            $wpdb->prepare(
                "DELETE FROM {$wpdb->postmeta} WHERE meta_key = %s",
                $meta_key
            )
        );
    }

    // Remove order meta data (profit calculations)
    $order_meta_keys = array(
        '_spvs_total_profit',
        '_spvs_line_profit',
        '_spvs_unit_cost',
    );

    foreach ( $order_meta_keys as $meta_key ) {
        $wpdb->query(
            $wpdb->prepare(
                "DELETE FROM {$wpdb->postmeta} WHERE meta_key = %s",
                $meta_key
            )
        );
    }

    // If WooCommerce HPOS is enabled, also remove from order meta table
    $orders_meta_table = $wpdb->prefix . 'wc_orders_meta';
    if ( $wpdb->get_var( "SHOW TABLES LIKE '{$orders_meta_table}'" ) === $orders_meta_table ) {
        foreach ( $order_meta_keys as $meta_key ) {
            $wpdb->query(
                $wpdb->prepare(
                    "DELETE FROM {$orders_meta_table} WHERE meta_key = %s",
                    $meta_key
                )
            );
        }
    }

    // Remove order item meta data
    $order_item_meta_keys = array(
        '_spvs_line_profit',
        '_spvs_unit_cost',
    );

    foreach ( $order_item_meta_keys as $meta_key ) {
        $wpdb->query(
            $wpdb->prepare(
                "DELETE FROM {$wpdb->prefix}woocommerce_order_itemmeta WHERE meta_key = %s",
                $meta_key
            )
        );
    }

    // Clear any cached data
    wp_cache_flush();
}

// Run the uninstall function
spvs_cost_profit_uninstall();
