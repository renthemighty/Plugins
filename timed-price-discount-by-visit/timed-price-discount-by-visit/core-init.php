<?php 
/*
*
*	***** timed-price-discount-by-visit *****
*
*	This file initializes all PBV Core components
*	
*/
// If this file is called directly, abort. //
if ( ! defined( 'WPINC' ) ) {die;} // end if
// Define Our Constants
define('PBV_CORE_INC',dirname( __FILE__ ).'/assets/inc/');
define('PBV_CORE_IMG',plugins_url( 'assets/img/', __FILE__ ));
define('PBV_CORE_CSS',plugins_url( 'assets/css/', __FILE__ ));
define('PBV_CORE_JS',plugins_url( 'assets/js/', __FILE__ ));
/*
*
*  Register CSS
*
*/
function pbv_register_core_css(){
wp_enqueue_style('pbv-core', PBV_CORE_CSS . 'pbv-core.css',null,time(),'all');
};
add_action( 'wp_enqueue_scripts', 'pbv_register_core_css' );    
/*
*
*  Register JS/Jquery Ready
*
*/
function pbv_register_core_js(){
// Register Core Plugin JS	
wp_enqueue_script('pbv-core', PBV_CORE_JS . 'pbv-core.js','jquery',time(),true);
};
add_action( 'wp_enqueue_scripts', 'pbv_register_core_js' );    
/*
*
*  Includes
*
*/ 
// Load the Functions
if ( file_exists( PBV_CORE_INC . 'pbv-core-functions.php' ) ) {
	require_once PBV_CORE_INC . 'pbv-core-functions.php';
}     
// Load the ajax Request
if ( file_exists( PBV_CORE_INC . 'pbv-ajax-request.php' ) ) {
	require_once PBV_CORE_INC . 'pbv-ajax-request.php';
} 
// Load the Shortcodes
if ( file_exists( PBV_CORE_INC . 'pbv-shortcodes.php' ) ) {
	require_once PBV_CORE_INC . 'pbv-shortcodes.php';
}