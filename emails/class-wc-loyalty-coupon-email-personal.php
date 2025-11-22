<?php
/**
 * WooCommerce Loyalty Coupon Email - Personal
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class WC_Loyalty_Coupon_Email_Personal extends WC_Email {

	/**
	 * Constructor
	 */
	public function __construct() {
		$this->id             = 'wc_loyalty_coupon_personal';
		$this->title          = 'Loyalty Coupon - Personal';
		$this->description    = 'Sent when a customer receives a personal loyalty coupon';
		$this->subject        = 'Your {site_title} Loyalty Coupon - ${coupon_amount}';
		$this->heading        = 'Your Loyalty Coupon';
		$this->template_base  = plugin_dir_path( __FILE__ ) . 'templates/';
		$this->template_html  = 'email-loyalty-coupon-personal.php';
		$this->template_plain = 'email-loyalty-coupon-personal-plain.txt';
		$this->placeholders   = array(
			'{site_title}'    => $this->get_blogname(),
			'{coupon_amount}' => '',
		);

		parent::__construct();
	}

	/**
	 * Trigger email
	 */
	public function trigger( $order_id, $coupon, $recipient_email ) {
		if ( ! $order_id || ! $coupon ) {
			return;
		}

		$order = wc_get_order( $order_id );
		if ( ! $order ) {
			return;
		}

		$this->object               = $order;
		$this->coupon               = $coupon;
		$this->recipient            = $recipient_email;
		$this->placeholders['{site_title}']    = $this->get_blogname();
		$this->placeholders['{coupon_amount}'] = wc_price( $coupon->get_amount() );

		$this->subject = sprintf( 'Your %s Loyalty Coupon - $%s', $this->get_blogname(), number_format( $coupon->get_amount(), 2 ) );
		$this->heading = 'Your Loyalty Coupon';

		if ( $this->is_enabled() && $recipient_email ) {
			$this->send( $recipient_email, $this->get_subject(), $this->get_content(), $this->get_headers(), $this->get_attachments() );
		}
	}

	/**
	 * Get email subject
	 */
	public function get_subject() {
		return apply_filters( 'woocommerce_email_subject_' . $this->id, $this->subject, $this->object );
	}

	/**
	 * Get email heading
	 */
	public function get_heading() {
		return apply_filters( 'woocommerce_email_heading_' . $this->id, $this->heading, $this->object );
	}

	/**
	 * Get email content HTML
	 */
	public function get_content_html() {
		if ( ! $this->coupon || ! $this->coupon->get_code() ) {
			return '';
		}

		$coupon_code = $this->coupon->get_code();
		$amount = wc_price( $this->coupon->get_amount() );
		$expires = $this->coupon->get_date_expires() ? $this->coupon->get_date_expires()->format( get_option( 'date_format' ) ) : 'Never';

		$html = '<h2>' . esc_html__( 'Thank you for your purchase!', 'wc-loyalty-coupon' ) . '</h2>';
		$html .= '<p>' . sprintf( esc_html__( 'As a valued customer, you\'ve earned a <strong>$%s loyalty coupon</strong> for your next purchase!', 'wc-loyalty-coupon' ), number_format( $this->coupon->get_amount(), 2 ) ) . '</p>';
		$html .= '<h3 style="color: #0073aa; margin-top: 20px;">' . esc_html__( 'Your Coupon Code', 'wc-loyalty-coupon' ) . '</h3>';
		$html .= '<div style="background: #f5f5f5; padding: 15px; border-left: 4px solid #0073aa; border-radius: 4px; margin: 20px 0;">';
		$html .= '<p style="font-size: 18px; font-weight: bold; color: #0073aa; margin: 0; letter-spacing: 2px;">' . esc_html( $coupon_code ) . '</p>';
		$html .= '</div>';
		$html .= '<h3>' . esc_html__( 'Coupon Details', 'wc-loyalty-coupon' ) . '</h3>';
		$html .= '<ul style="list-style: none; padding: 0; margin: 10px 0;">';
		$html .= '<li style="padding: 5px 0;"><strong>' . esc_html__( 'Discount:', 'wc-loyalty-coupon' ) . '</strong> ' . $amount . '</li>';
		$html .= '<li style="padding: 5px 0;"><strong>' . esc_html__( 'Valid Until:', 'wc-loyalty-coupon' ) . '</strong> ' . esc_html( $expires ) . '</li>';
		$html .= '<li style="padding: 5px 0;"><strong>' . esc_html__( 'Usage:', 'wc-loyalty-coupon' ) . '</strong> ' . esc_html__( 'Once per customer', 'wc-loyalty-coupon' ) . '</li>';
		$html .= '</ul>';
		$html .= '<p style="margin-top: 20px;">' . sprintf( esc_html__( 'Apply this coupon at checkout on your next purchase at %s to get your discount!', 'wc-loyalty-coupon' ), esc_html( get_option( 'blogname' ) ) ) . '</p>';
		$html .= '<p>' . esc_html__( 'Happy shopping!', 'wc-loyalty-coupon' ) . '</p>';

		return $html;
	}

	/**
	 * Get email content plain text
	 */
	public function get_content_plain() {
		if ( ! $this->coupon || ! $this->coupon->get_code() ) {
			return '';
		}

		$coupon_code = $this->coupon->get_code();
		$expires = $this->coupon->get_date_expires() ? $this->coupon->get_date_expires()->format( get_option( 'date_format' ) ) : 'Never';

		$text = "Thank you for your purchase!\n\n";
		$text .= "As a valued customer, you've earned a $" . number_format( $this->coupon->get_amount(), 2 ) . " loyalty coupon for your next purchase!\n\n";
		$text .= "YOUR COUPON CODE:\n";
		$text .= "$coupon_code\n\n";
		$text .= "COUPON DETAILS:\n";
		$text .= "Discount: $" . number_format( $this->coupon->get_amount(), 2 ) . "\n";
		$text .= "Valid Until: $expires\n";
		$text .= "Usage: Once per customer\n\n";
		$text .= "Apply this coupon at checkout on your next purchase at " . get_option( 'blogname' ) . " to get your discount!\n\n";
		$text .= "Happy shopping!";

		return $text;
	}

	/**
	 * Get email subject
	 */
	public function get_default_subject() {
		return __( 'Your {site_title} Loyalty Coupon', 'wc-loyalty-coupon' );
	}

	/**
	 * Get email heading
	 */
	public function get_default_heading() {
		return __( 'Your Loyalty Coupon', 'wc-loyalty-coupon' );
	}
}
