<?php
/**
 * WooCommerce Loyalty Coupon Email - Personal
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class WC_Loyalty_Coupon_Email_Personal extends WC_Email {

	public $coupon;
	public $recipient_email;

	public function __construct() {
		$this->id             = 'wc_loyalty_coupon_personal';
		$this->title          = 'Loyalty Coupon - Personal';
		$this->description    = 'Sent when customer receives personal loyalty coupon';
		$this->subject        = 'Your Loyalty Coupon - ${coupon_amount}';
		$this->heading        = 'Your Loyalty Coupon';

		parent::__construct();
	}

	public function trigger( $order_id, $coupon, $recipient_email ) {
		$this->object          = wc_get_order( $order_id );
		$this->coupon          = $coupon;
		$this->recipient_email = $recipient_email;

		if ( ! $this->is_enabled() || ! $this->get_recipient() ) {
			return;
		}

		$this->send( $this->get_recipient(), $this->get_subject(), $this->get_content(), $this->get_headers(), $this->get_attachments() );
	}

	public function get_recipient() {
		return $this->recipient_email;
	}

	public function get_subject() {
		$amount = $this->coupon ? number_format( $this->coupon->get_amount(), 2 ) : '0.00';
		return apply_filters( 'woocommerce_email_subject_' . $this->id, "Your \${$amount} Loyalty Coupon", $this->object );
	}

	public function get_heading() {
		return apply_filters( 'woocommerce_email_heading_' . $this->id, 'Your Loyalty Coupon', $this->object );
	}

	public function get_content_html() {
		if ( ! $this->coupon || ! $this->coupon->get_code() ) {
			return '<p>Error: Coupon not found.</p>';
		}

		$coupon_code = esc_html( $this->coupon->get_code() );
		$amount = number_format( $this->coupon->get_amount(), 2 );
		$expires = $this->coupon->get_date_expires() ? $this->coupon->get_date_expires()->format( get_option( 'date_format' ) ) : 'Never';

		$html = '<h2>Thank you for your purchase!</h2>';
		$html .= '<p>As a valued customer, you\'ve earned a <strong>$' . $amount . ' loyalty coupon</strong> for your next purchase!</p>';
		$html .= '<h3 style="color: #0073aa; margin-top: 20px;">Your Coupon Code</h3>';
		$html .= '<div style="background: #f5f5f5; padding: 15px; border-left: 4px solid #0073aa; border-radius: 4px; margin: 20px 0;">';
		$html .= '<p style="font-size: 18px; font-weight: bold; color: #0073aa; margin: 0; letter-spacing: 2px;">' . $coupon_code . '</p>';
		$html .= '</div>';
		$html .= '<h3>Coupon Details</h3>';
		$html .= '<ul style="list-style: none; padding: 0;">';
		$html .= '<li><strong>Discount:</strong> $' . $amount . '</li>';
		$html .= '<li><strong>Valid Until:</strong> ' . esc_html( $expires ) . '</li>';
		$html .= '<li><strong>Usage:</strong> Once per customer</li>';
		$html .= '</ul>';
		$html .= '<p style="margin-top: 20px;">Apply this coupon at checkout on your next purchase to get your discount!</p>';
		$html .= '<p>Happy shopping!</p>';

		return $html;
	}

	public function get_content_plain() {
		if ( ! $this->coupon || ! $this->coupon->get_code() ) {
			return 'Error: Coupon not found.';
		}

		$coupon_code = $this->coupon->get_code();
		$amount = number_format( $this->coupon->get_amount(), 2 );
		$expires = $this->coupon->get_date_expires() ? $this->coupon->get_date_expires()->format( get_option( 'date_format' ) ) : 'Never';

		$text = "Thank you for your purchase!\n\n";
		$text .= "As a valued customer, you've earned a \$$amount loyalty coupon for your next purchase!\n\n";
		$text .= "YOUR COUPON CODE:\n";
		$text .= "$coupon_code\n\n";
		$text .= "COUPON DETAILS:\n";
		$text .= "Discount: \$$amount\n";
		$text .= "Valid Until: $expires\n";
		$text .= "Usage: Once per customer\n\n";
		$text .= "Apply this coupon at checkout on your next purchase to get your discount!\n\n";
		$text .= "Happy shopping!";

		return $text;
	}
}
