<?php
/*
 * Plugin Name: First Order Free Product
 * Author: Megatron
 * Author URI: https://metwrk.com
 * Version: 1.1
 * Description: "Offer your customers a free gift with their first purchase. You can use a live product, or create a product that is Catalog visibility: Hidden to use an unpublished product
*/
if ( ! defined( 'ABSPATH' ) ) { 
    exit; // Exit if accessed directly
}
/**
 * Check if WooCommerce is active
 **/
if ( in_array( 'woocommerce/woocommerce.php', apply_filters( 'active_plugins', get_option( 'active_plugins' ) ) ) ) {
    
    require_once ('fofp-admin.php');
    require_once ('fofp-coupon.php');

	
}

?>