<?php
/**
 * Email template for personal loyalty coupons
 *
 * @package WooCommerce Loyalty Coupon
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

do_action( 'woocommerce_email_header', $email_heading, $email ); ?>

	<p><?php _e( 'Thank you for your purchase!', 'wc-loyalty-coupon' ); ?></p>

	<p><?php printf( __( 'As a valued customer, you\'ve earned a <strong>$%s loyalty coupon</strong> for your next purchase!', 'wc-loyalty-coupon' ), wc_price( $coupon->get_amount() ) ); ?></p>

	<h2 style="color: #0073aa; margin-top: 20px; margin-bottom: 10px;"><?php _e( 'Your Coupon Code', 'wc-loyalty-coupon' ); ?></h2>

	<div style="background: #f5f5f5; padding: 15px; border-left: 4px solid #0073aa; border-radius: 4px; margin: 20px 0;">
		<p style="font-size: 18px; font-weight: bold; color: #0073aa; margin: 0; letter-spacing: 2px;">
			<?php echo esc_html( $coupon->get_code() ); ?>
		</p>
	</div>

	<h3><?php _e( 'Coupon Details', 'wc-loyalty-coupon' ); ?></h3>

	<ul style="list-style: none; padding: 0; margin: 10px 0;">
		<li style="padding: 5px 0;"><strong><?php _e( 'Discount:', 'wc-loyalty-coupon' ); ?></strong> <?php echo wc_price( $coupon->get_amount() ); ?></li>
		<li style="padding: 5px 0;"><strong><?php _e( 'Valid Until:', 'wc-loyalty-coupon' ); ?></strong> <?php echo $coupon->get_date_expires() ? $coupon->get_date_expires()->format( get_option( 'date_format' ) ) : __( 'Never', 'wc-loyalty-coupon' ); ?></li>
		<li style="padding: 5px 0;"><strong><?php _e( 'Usage:', 'wc-loyalty-coupon' ); ?></strong> <?php _e( 'Once per customer', 'wc-loyalty-coupon' ); ?></li>
	</ul>

	<p style="margin-top: 20px;">
		<?php printf(
			__( 'Apply this coupon at checkout on your next purchase at %s to get your discount!', 'wc-loyalty-coupon' ),
			esc_html( get_option( 'blogname' ) )
		); ?>
	</p>

	<p><?php _e( 'Happy shopping!', 'wc-loyalty-coupon' ); ?></p>

<?php do_action( 'woocommerce_email_footer', $email );
