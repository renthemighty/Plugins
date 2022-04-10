<?php

add_action('woocommerce_product_options_general_product_data', 'pbv_product_custom_fields');

function pbv_product_custom_fields()
{
    global $woocommerce, $post;
    
    echo '<div class="pbv_product_custom_field">';
    
    woocommerce_wp_text_input(
        array(
            'id' => '_visit_price_count',
            'placeholder' => '',
            'label' => __('Visits to Discount', 'woocommerce'),
            'type' => 'number',
            'custom_attributes' => array(
                'step' => 'any',
                'min' => '0'
                )
            )
        );
        
    woocommerce_wp_text_input(
        array(
            'id' => '_visit_price',
            'placeholder' => '',
            'label' => __('Discounted Price', 'woocommerce'),
            'desc_tip' => 'true'
            )
        );
        
     woocommerce_wp_textarea_input(
        array(
            'id' => '_visit_price_message',
            'placeholder' => '',
            'label' => __('Discount Message', 'woocommerce')
            )
        );
    
    echo '</div>';

}


add_action('woocommerce_process_product_meta', 'pbv_woocommerce_product_custom_fields_save');

function pbv_woocommerce_product_custom_fields_save($post_id)
{
   
    $woocommerce_visit_price = $_POST['_visit_price'];
    if (empty($woocommerce_visit_price))
    $woocommerce_visit_price ='';
        update_post_meta($post_id, '_visit_price', esc_attr($woocommerce_visit_price));
        
        
    $woocommerce_visit_price_count = $_POST['_visit_price_count'];
    if (empty($woocommerce_visit_price_count))
    $woocommerce_visit_price_count ='';
        update_post_meta($post_id, '_visit_price_count', esc_attr($woocommerce_visit_price_count));
        
        
     $woocommerce_visit_price_message = $_POST['_visit_price_message'];
    if (empty($woocommerce_visit_price_message))
    $woocommerce_visit_price_message='';
        update_post_meta($post_id, '_visit_price_message', esc_html($woocommerce_visit_price_message));

}

add_filter('woocommerce_product_get_price', 'pbv_return_offer_price', 10, 2);

function pbv_return_offer_price($price, $product) {
    if(is_product()){
        $load_count = get_post_meta( $product->get_id(), '_visit_price_count', true );
        $load_price = get_post_meta( $product->get_id(), '_visit_price', true );
        if ( ! empty( $load_count ) ){
            if ( ! empty(  $load_price ) ){
             
                $loadedcount = pbv_cookies_get_products($product->get_id());
                if($loadedcount == $load_count  ){
                    $prid = $product->get_id();
                    $price =  $load_price;
                    
                    WC()->session->set($prid, $price);
                }
            }
        }
        
    }
    return $price;

}


add_action( 'woocommerce_before_calculate_totals', 'pbv_set_custom_cart_item_price', 20, 1 );

function pbv_set_custom_cart_item_price( $wc_cart ) {


    foreach ( $wc_cart->get_cart() as $key => $cart_item ){

        $pid = $cart_item['product_id'];
        $sessionprice = WC()->session->get($pid);
        
        if($sessionprice){
            $load_price = get_post_meta( $pid, '_visit_price', true );
            
            if($load_price){
                $cart_item['data']->set_price( $sessionprice );
            }
        } 
    }
}


add_action( 'woocommerce_cart_item_removed', 'pbv_after_remove_product_from_cart', 10, 2 );

function pbv_after_remove_product_from_cart($removed_cart_item_key, $cart) {
    
    $line_item = $cart->removed_cart_contents[ $removed_cart_item_key ];
    $pid = $line_item[ 'product_id' ];
    $sessionprice = WC()->session->get($pid);
    if($sessionprice){
        WC()->session->set($pid, null);
    }
}



add_action( 'woocommerce_single_product_summary', 'pbv_custom_field_display_below_title', 2 );

function pbv_custom_field_display_below_title(){
    
    global $product;

    $load_count = get_post_meta( $product->get_id(), '_visit_price_count', true );
    $load_price = get_post_meta( $product->get_id(), '_visit_price', true );
    $load_message = get_post_meta( $product->get_id(), '_visit_price_message', true );
    if ( ! empty( $load_count ) ) {
         if ( ! empty(  $load_message ) ) {
             
             $loadedcount = pbv_cookies_get_products($product->get_id());
             if($loadedcount == $load_count  ){ 
               echo '<p class="onetime_price">'.$load_message.'</p>';
             }
        }
    }
}

add_action( 'woocommerce_add_to_cart', 'custom_add_to_cart', 10, 2 );
function custom_add_to_cart( $cart_item_key, $product_id ) {

    $load_count = get_post_meta( $product_id, '_visit_price_count', true );
    $load_price = get_post_meta( $product_id, '_visit_price', true );
    if ( ! empty( $load_count ) ) {
      
             
             $loadedcount = pbv_cookies_get_products($product_id);
             if($loadedcount == $load_count+1  ){ 
               
               
        }
    }
    
}

function pbv_get_the_user_ip() {
    
    if ( ! empty( $_SERVER['HTTP_CLIENT_IP'] ) ) {

        $ip = $_SERVER['HTTP_CLIENT_IP'];
    } elseif ( ! empty( $_SERVER['HTTP_X_FORWARDED_FOR'] ) ) {

        $ip = $_SERVER['HTTP_X_FORWARDED_FOR'];
    } else {
        $ip = $_SERVER['REMOTE_ADDR'];
    }
    return $ip;
}


function pbv_cookies_set_products($post_id) { 

    $visitor_ip_raw = pbv_get_the_user_ip();
    $visit_count = 2;
    
    $pbvs =  array("vip"=>$visitor_ip_raw,"pid"=>$post_id,"vcount"=>$visit_count);
    $pbvsencoded = json_encode($pbvs);
    
    if(isset($_COOKIE['pbv'])) {

        $cookieval= $_COOKIE['pbv'];
        $cookieval = json_decode(stripslashes($cookieval), true);
        $visit_count = $cookieval['vcount'];
        $visit_ip = $cookieval['vip'];
        $visit_post = $cookieval['pid'];
           
        if($visit_ip == $visitor_ip_raw && $visit_post == $post_id ){
            
               $visit_count++;
        }
           
        setcookie('pbv', '', time()-96400);
        
        $pbvs =  array("vip"=>$visitor_ip_raw,"pid"=>$post_id,"vcount"=>$visit_count);
        $pbvsencoded = json_encode($pbvs);
    }
    
    setcookie('pbv', $pbvsencoded, time()+86400);
} 


function pbv_cookies_get_products($post_id) { 
   
    $visit_count = 1;
    $ret =$visit_count;
    if(isset($_COOKIE['pbv'])) {
        $cookieval= $_COOKIE['pbv'];
        $cookieval = json_decode(stripslashes($cookieval), true);
        $visit_count = $cookieval['vcount'];
        $visit_ip = $cookieval['vip'];
        $visit_post = $cookieval['pid'];
        $ret = $visit_count;
    }
    return $ret;
}


add_action('template_redirect', 'pbv_product_cookie');

function pbv_product_cookie() {
    if (is_single()){
        $postNumber = get_the_ID();
        pbv_cookies_set_products($postNumber);
    }
}


add_action('woocommerce_init', 'pbv_force_non_logged_user_wc_session');

function pbv_force_non_logged_user_wc_session()
{
    if (is_user_logged_in() || is_admin())
        return;
    if (isset(WC()->session)) {
        if (!WC()->session->has_session()) {
            WC()->session->set_customer_session_cookie(true);
       }
    }
}


?>
