<?php
if ( ! defined( 'ABSPATH' ) ) { 
    exit; // Exit if accessed directly
}

add_action( 'woocommerce_before_cart', 'fofp_apply_discount' );
add_action( 'woocommerce_checkout_init', 'fofp_apply_discount' );

function fofp_apply_discount() {
    
    global $wpdb;

    $strData = get_option('_fofp_configuration');
    $arrData = unserialize($strData);
    if($arrData['enableMinCart']){
    $cart_total = $arrData['minCartValue'];
    }else{
    $cart_total = 0;
    }
    // if disabled, then don't do anything
    if($arrData['type'] == 'disable' || (isset($arrData['autoApplyGuest']) && ($arrData['autoApplyGuest'] == 'no' || $arrData['autoApplyGuest'] == '') && !get_current_user_id())) {
        return;
    }

    if(fofp_has_bought()) {
    	return;
    }

    $productInCart = false;
    foreach( WC()->cart->get_cart() as $cart_item_key => $values ) {
        $_product = $values['data'];
    
        if( $arrData['freeProduct'] == $_product->get_id() ) {
            $productInCart = true;
        }
    }
    if( WC()->cart->subtotal >= $cart_total) {
        if($productInCart==false){
            WC()->cart->add_to_cart( $arrData['freeProduct'] );
        }
            }
    $in_cart = 0;
    $in_cart_others = 0;
    foreach( WC()->cart->get_cart() as $cart_item_key => $cart_item ) {
      if ( $cart_item['product_id'] == $arrData['freeProduct'] ) {
         $key = $cart_item_key;
        $in_cart = 1;
      }else{
          $in_cart_others = 1;
      }
   }
   
      if ( $in_cart !=0 &&  WC()->cart->subtotal <= $cart_total){
          
          if($in_cart_others==0){
          WC()->cart->empty_cart();
      }else{
          WC()->cart->remove_cart_item( $key );
      }
      } 
}

/*
 * This function will check if customer has purchased any product.
 * Date: 17-08-2017
 * Author: Vidish Purohit
 */
function fofp_has_bought() {

    $count = 0;
    $bought = false;

    if(!get_current_user_id()) {
        return false;
    }

    // Get all customer orders
    $customer_orders = get_posts( array(
        'numberposts' => -1,
        'meta_key'    => '_customer_user',
        'meta_value'  => get_current_user_id(),
        'post_type'   => 'shop_order', // WC orders post type
        'post_status' => array('wc-completed', 'wc-in-progress', 'in-progress', 'wc-processing', 'wc-on-hold','wc-pending') // Only orders with status "completed" & "In  Progress"
    ) );

    // Going through each current customer orders
    foreach ( $customer_orders as $customer_order ) {
        $count++;
    }

    // return "true" when customer has already one order
    if ( $count > 0 ) {
        $bought = true;
    }
    return $bought;
}