<?php
if ( ! defined( 'ABSPATH' ) ) { 
    exit; // Exit if accessed directly
}

/*
 * This function will register the menu page for the admin of the first-order discount.
 */
function fofp_register_submenu_page() {
    add_submenu_page( 'woocommerce', __('First Order Free Product'), __('First Order Free Product'), 'manage_options', 'first-order-free-product', 'fofp_discount' ); 
}
add_action('admin_menu', 'fofp_register_submenu_page');

/*
 * This function will manage the display of the admin interface.
 */
function fofp_discount() {

	global $wpdb;

	notify_coupon_status();

	if(isset($_POST) && !empty($_POST)) {
		fofp_save_discount();
	}
	$arrData = unserialize(get_option('_fofp_configuration')); ?>

	<h2 style=" text-align: center; font-size: 30px; margin-bottom: 50px; ">First Order Free Product Configuration</h2>
	<form method="POST">
		<table>
			
			<tr>
				<th style="width:250px;text-align:left;"><label>Free Product Status</label></th>
				<td>
					<input type="radio" name="rdoDiscType" value="free_product" id="rdoFreeProduct" onclick="javascript:checkFreeProduct();" <?php echo isset($arrData['type']) && $arrData['type'] == 'free_product'?" checked='checked'":'';?>><label for="rdoFreeProduct">Enabled</label>
				<br/><br/>
				<input type="radio" name="rdoDiscType" value="disable" id="rdoDisable" onclick="javascript:checkFreeProduct();"><label for="rdoDisable" <?php echo isset($arrData['type']) && $arrData['type'] == 'disable'?" checked='checked'":'';?>>Disable</label>
				</td>
			</tr>
			
			<?php

			// Get products
			$strProduct = "SELECT post_title, ID FROM {$wpdb->prefix}posts WHERE post_type = 'product' AND post_status = 'publish'";
			$arrProduct = $wpdb->get_results($strProduct);
    		
			?><tr id="trFreeProduct" style="display:none;">
				<th style="width:250px;text-align:left;">
					<label for="txtAmount"><?php _e('Select free product');?></label>
					<span class="help tooltip">?<span class="tooltiptext">We recommend using simple products for giving free.</span></span>
				</th>
				<td>
					<select id="selFreeProduct" name="selFreeProduct" style="width:200px;">
						<option value="">Please choose product</option><?php
						foreach ($arrProduct as $key => $value) {
							echo '<option value="' .$value->ID  . '"' . (isset($arrData['freeProduct']) && $arrData['freeProduct'] == $value->ID?' selected="selected"':'') . '>' . $value->post_title . '</option>';
						}
					?></select>
				</td>
			</tr>
			
		
			
			<tr>
				<th style="width:250px;text-align:left;"><label for="chkEnableMinCartAmt"><?php _e('Enable minimum cart amount');?></label>
					
				</th>
				<td>
					<input type="checkbox" name="chkEnableMinCartAmt" <?php if($arrData['enableMinCart']){ ?>checked="checked" <?php } ?> value="yes" id="chkEnableMinCartAmt" onclick="javascript:checkVisible();">
				</td>
			</tr>
			<tr id="trMinCart" style="display:none;">
				<th style="width:250px;text-align:left;">
					<label for="txtMinCartAmount"><?php _e('Minimum cart value');?></label>
					
				</th>
				<td>
					<input type="text" name="txtMinCartAmount" value="<?php echo $arrData['minCartValue']; ?>" id="txtMinCartAmount" placeholder="Minimum cart amount">
				</td>
			</tr>
			<tr>
				<td colspan="2"><input type="submit" value="Save" class="button button-primary"></td>
			</tr>
		</table>
	</form><?php

}

// notify admin to enable coupon
function notify_coupon_status() {
	
	if(get_option('woocommerce_enable_coupons') == 'yes') {
		return;
	}

	echo '<div class="notice notice-error is-dismissible"> 
		<p><strong>This plugin needs coupons enabled in order to work.</strong></p>
		<button type="button" class="notice-dismiss">
			<span class="screen-reader-text">Dismiss this notice.</span>
		</button>
	</div>';
	
}

add_action( 'admin_enqueue_scripts', 'fofp_load_admin_script' );
function fofp_load_admin_script() {
    wp_register_script( 'fofp_select2', plugin_dir_url( __FILE__ ) . 'assets/js/select2.full.js', array(), false, '1.0.0' );
    wp_enqueue_script( 'fofp_select2' );

    wp_register_script( 'fofp_discount_admin_js', plugin_dir_url( __FILE__ ) . 'assets/js/fofp_control.js', array(), false, '1.0.0' );
    wp_enqueue_script( 'fofp_discount_admin_js' );

    wp_enqueue_style( 'fofp_css', plugin_dir_url( __FILE__ ) . 'assets/css/fofp_admin.css');
    wp_enqueue_style( 'fofp_select2', plugin_dir_url( __FILE__ ) . 'assets/css/select2.min.css');

    // Localize the script
    $translation_array = array(
        'admin_url' => admin_url('admin-ajax.php')
    );
    wp_localize_script( 'fofp_discount_admin_js', 'fofp_obj', $translation_array );
}


function fofp_save_discount() {

	$arrData = array();
	$arrData['type'] = sanitize_title($_POST['rdoDiscType']);
	$arrData['discValue'] = sanitize_title($_POST['txtAmount']);
	$arrData['freeProduct'] = sanitize_title($_POST['selFreeProduct']);
	$arrData['enableMinCart'] = sanitize_title($_POST['chkEnableMinCartAmt']);
	$arrData['minCartValue'] = sanitize_title($_POST['txtMinCartAmount']);
	$arrData['isIndUseOnly'] = sanitize_title($_POST['chkIndividualUseOnly']);
	$arrData['autoApplyGuest'] = isset($_POST['chkEnableGuest']) && !empty($_POST['chkEnableGuest']) && $_POST['chkEnableGuest'] == 'yes'?'yes':'no';

	// Update coupon
	$intCouponId = get_option('_fofp_coupon_id');

	// update shipping
	if($arrData['type'] == 'free_shipping') {
		update_post_meta( $intCouponId, 'free_shipping', 'yes' );
		$arrData['discValue'] = 0;
	} else {
		update_post_meta( $intCouponId, 'free_shipping', 'no' );
	}
	update_post_meta( $intCouponId, 'usage_limit_per_user', '1');
	// update discount type
	if($arrData['type'] == 'percentage_discount') {
		update_post_meta( $intCouponId, 'discount_type', 'percent' );
	} else if($arrData['type'] == 'fix_discount') {
		update_post_meta( $intCouponId, 'discount_type', 'fixed_cart' );
	} 
	update_post_meta( $intCouponId, 'coupon_amount', $arrData['discValue'] );

	update_post_meta( $intCouponId, 'minimum_amount', '' );

	if(isset($arrData['isIndUseOnly']) && $arrData['isIndUseOnly'] == 'yes') {
		update_post_meta( $intCouponId, 'individual_use', 'yes' );
	} else {
		update_post_meta( $intCouponId, 'individual_use', 'no' );
	}
	update_option('_fofp_configuration', serialize($arrData));
}

add_filter( 'admin_footer_text', 'fofp_admin_footer_text', 1 );
function fofp_admin_footer_text( $footer_text ) {
    if ( ! current_user_can( 'manage_woocommerce' ) || ! function_exists( 'wc_get_screen_ids' ) ) {
        return $footer_text;
    }
    $current_screen = get_current_screen();
    
    // Check to make sure we're on a discount admin page.
    if ( isset( $current_screen->id ) && $current_screen->id == 'woocommerce_page_first-order-discount-woocommerce' ) {
        
        /* translators: %s: five stars */
        $footer_text = sprintf( __( 'For support, write us at : info@wooextend.com and if you like <strong>First Order Discount Woocommerce</strong> please leave us a %s rating. A huge thanks in advance!', 'woocommerce' ), '<a href="https://wordpress.org/support/plugin/first-order-discount-woocommerce/reviews?rate=5#new-post" target="_blank" class="wc-rating-link" data-rated="' . esc_attr__( 'Thanks :)', 'woocommerce' ) . '">&#9733;&#9733;&#9733;&#9733;&#9733;</a>' );
        wc_enqueue_js( "
            jQuery( 'a.wc-rating-link' ).click( function() {
                jQuery.post( '" . WC()->ajax_url() . "', { action: 'woocommerce_rated' } );
                jQuery( this ).parent().text( jQuery( this ).data( 'rated' ) );
            });
        " );
        
    }

    return $footer_text;
}