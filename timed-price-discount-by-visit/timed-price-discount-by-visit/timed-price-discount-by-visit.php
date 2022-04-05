<?php 

/*
 * Plugin Name: Timed Price Discount by Visit
 * Author: MetWrk SafeHouse
 * Author URI: https://metwrk.com
 * Version: 1.1.1
 * Description: "Plugin to set price based on page visits. Set the number to 1 for the first visit, and subsequently 5 for the 5th-page visit. There you can set a price and a message. Accepts HTML for the message to the user
*/

// If this file is called directly, abort. //
if ( ! defined( 'WPINC' ) ) {die;} // end if

// Let's Initialize Everything
if ( file_exists( plugin_dir_path( __FILE__ ) . 'core-init.php' ) ) {
require_once( plugin_dir_path( __FILE__ ) . 'core-init.php' );
}

if ( file_exists( plugin_dir_path( __FILE__ ) . 'inc/pbv-functions.php' ) ) {
require_once( plugin_dir_path( __FILE__ ) . 'inc/pbv-functions.php' );
}

?>