<?php
/**
 * Plugin Name: WooCommerce Category Banner
 * Plugin URI:  https://github.com/renthemighty/woocommerce-category-banner
 * Description: Add full-width banners to WooCommerce product category pages with flexible positioning and image cropping.
 * Version:     1.0.0
 * Author:      Megatron
 * Author URI:  https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.4
 * Requires PHP: 7.2
 * WC requires at least: 5.0
 * WC tested up to: 8.5
 * License:     GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: wc-category-banner
 */

defined( 'ABSPATH' ) || exit;

class WC_Category_Banner {

	private static $instance = null;

	const META_IMAGE_ID   = '_wc_cat_banner_image_id';
	const META_POSITION   = '_wc_cat_banner_position';
	const META_CROP_MODE  = '_wc_cat_banner_crop_mode';
	const META_CROP_DATA  = '_wc_cat_banner_crop_data';
	const META_CROPPED_ID = '_wc_cat_banner_cropped_id';
	const META_MAX_HEIGHT = '_wc_cat_banner_max_height';
	const NONCE_ACTION    = 'wc_cat_banner_save';
	const NONCE_FIELD     = '_wc_cat_banner_nonce';
	const CROP_NONCE      = 'wc_cat_banner_crop';

	public static function instance() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	private function __construct() {
		/* --- Admin: category form fields --- */
		add_action( 'product_cat_add_form_fields', array( $this, 'add_category_fields' ), 20 );
		add_action( 'product_cat_edit_form_fields', array( $this, 'edit_category_fields' ), 20 );
		add_action( 'created_product_cat', array( $this, 'save_category_fields' ) );
		add_action( 'edited_product_cat', array( $this, 'save_category_fields' ) );

		/* --- Admin: scripts & styles on edit-tags pages --- */
		add_action( 'admin_enqueue_scripts', array( $this, 'admin_enqueue' ) );

		/* --- AJAX: server-side crop --- */
		add_action( 'wp_ajax_wc_cat_banner_crop', array( $this, 'ajax_crop_image' ) );

		/* --- Frontend: banners --- */
		add_action( 'woocommerce_before_shop_loop', array( $this, 'render_inside_top' ), 5 );
		add_action( 'woocommerce_after_shop_loop', array( $this, 'render_inside_bottom' ), 15 );
		add_action( 'woocommerce_before_main_content', array( $this, 'render_full_width' ), 5 );

		/* --- Frontend: inline styles --- */
		add_action( 'wp_head', array( $this, 'frontend_css' ) );

		/* --- HPOS compatibility --- */
		add_action( 'before_woocommerce_init', function () {
			if ( class_exists( \Automattic\WooCommerce\Utilities\FeaturesUtil::class ) ) {
				\Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility( 'custom_order_tables', __FILE__, true );
			}
		} );
	}

	/* =========================================================================
	   Admin – "Add New Category" fields
	   ========================================================================= */

	public function add_category_fields() {
		wp_nonce_field( self::NONCE_ACTION, self::NONCE_FIELD );
		?>
		<div class="form-field" id="wc-cat-banner-wrap">
			<label><?php esc_html_e( 'Category Banner', 'wc-category-banner' ); ?></label>

			<div id="wc-cat-banner-preview" style="display:none;margin-bottom:10px;">
				<img id="wc-cat-banner-img" src="" style="max-width:100%;height:auto;" />
			</div>

			<div id="wc-cat-banner-cropper-wrap" style="display:none;margin-bottom:10px;">
				<p><strong><?php esc_html_e( 'Crop your banner:', 'wc-category-banner' ); ?></strong></p>
				<div id="wc-cat-banner-cropper-container" style="max-width:100%;max-height:500px;overflow:hidden;">
					<img id="wc-cat-banner-crop-img" src="" style="max-width:100%;" />
				</div>
				<p style="margin-top:8px;">
					<button type="button" class="button" id="wc-cat-banner-apply-crop">
						<?php esc_html_e( 'Apply Crop', 'wc-category-banner' ); ?>
					</button>
					<span id="wc-cat-banner-crop-status" style="margin-left:8px;"></span>
				</p>
			</div>

			<div id="wc-cat-banner-cropped-preview" style="display:none;margin-bottom:10px;">
				<p><strong><?php esc_html_e( 'Cropped Preview:', 'wc-category-banner' ); ?></strong></p>
				<img id="wc-cat-banner-cropped-img" src="" style="max-width:100%;height:auto;" />
			</div>

			<p>
				<button type="button" class="button" id="wc-cat-banner-upload">
					<?php esc_html_e( 'Upload Banner', 'wc-category-banner' ); ?>
				</button>
				<button type="button" class="button" id="wc-cat-banner-remove" style="display:none;">
					<?php esc_html_e( 'Remove Banner', 'wc-category-banner' ); ?>
				</button>
			</p>

			<input type="hidden" name="wc_cat_banner_image_id" id="wc-cat-banner-image-id" value="" />
			<input type="hidden" name="wc_cat_banner_cropped_id" id="wc-cat-banner-cropped-id" value="" />
			<input type="hidden" name="wc_cat_banner_crop_data" id="wc-cat-banner-crop-data" value="" />
		</div>

		<div class="form-field">
			<label for="wc-cat-banner-position"><?php esc_html_e( 'Banner Position', 'wc-category-banner' ); ?></label>
			<select name="wc_cat_banner_position" id="wc-cat-banner-position">
				<option value="inside-top"><?php esc_html_e( 'Inside container — Top (above products)', 'wc-category-banner' ); ?></option>
				<option value="inside-bottom"><?php esc_html_e( 'Inside container — Bottom (below products)', 'wc-category-banner' ); ?></option>
				<option value="full-width"><?php esc_html_e( 'Full page width (outside product container)', 'wc-category-banner' ); ?></option>
			</select>
		</div>

		<div class="form-field">
			<label for="wc-cat-banner-crop-mode"><?php esc_html_e( 'Crop Mode', 'wc-category-banner' ); ?></label>
			<select name="wc_cat_banner_crop_mode" id="wc-cat-banner-crop-mode">
				<option value="auto"><?php esc_html_e( 'Automatic (CSS-based responsive fit)', 'wc-category-banner' ); ?></option>
				<option value="manual"><?php esc_html_e( 'Manual (crop with visual editor)', 'wc-category-banner' ); ?></option>
			</select>
		</div>

		<div class="form-field" id="wc-cat-banner-maxheight-field">
			<label for="wc-cat-banner-max-height"><?php esc_html_e( 'Banner Max Height (px)', 'wc-category-banner' ); ?></label>
			<input type="number" name="wc_cat_banner_max_height" id="wc-cat-banner-max-height" value="400" min="0" max="2000" step="10" />
			<p class="description"><?php esc_html_e( 'Maximum banner height in pixels. Used for automatic crop mode. Set 0 for no limit.', 'wc-category-banner' ); ?></p>
		</div>
		<?php
	}

	/* =========================================================================
	   Admin – "Edit Category" fields (table row layout)
	   ========================================================================= */

	public function edit_category_fields( $term ) {
		$image_id   = absint( get_term_meta( $term->term_id, self::META_IMAGE_ID, true ) );
		$position   = get_term_meta( $term->term_id, self::META_POSITION, true ) ?: 'inside-top';
		$crop_mode  = get_term_meta( $term->term_id, self::META_CROP_MODE, true ) ?: 'auto';
		$crop_data  = get_term_meta( $term->term_id, self::META_CROP_DATA, true ) ?: '';
		$cropped_id = absint( get_term_meta( $term->term_id, self::META_CROPPED_ID, true ) );
		$max_height = get_term_meta( $term->term_id, self::META_MAX_HEIGHT, true );
		$max_height = ( '' === $max_height ) ? 400 : absint( $max_height );

		$image_url   = $image_id ? wp_get_attachment_url( $image_id ) : '';
		$cropped_url = $cropped_id ? wp_get_attachment_url( $cropped_id ) : '';

		wp_nonce_field( self::NONCE_ACTION, self::NONCE_FIELD );
		?>
		<tr class="form-field" id="wc-cat-banner-wrap">
			<th scope="row"><label><?php esc_html_e( 'Category Banner', 'wc-category-banner' ); ?></label></th>
			<td>
				<div id="wc-cat-banner-preview" style="<?php echo $image_url ? '' : 'display:none;'; ?>margin-bottom:10px;">
					<img id="wc-cat-banner-img" src="<?php echo esc_url( $image_url ); ?>" style="max-width:100%;height:auto;" />
				</div>

				<div id="wc-cat-banner-cropper-wrap" style="display:none;margin-bottom:10px;">
					<p><strong><?php esc_html_e( 'Crop your banner:', 'wc-category-banner' ); ?></strong></p>
					<div id="wc-cat-banner-cropper-container" style="max-width:100%;max-height:500px;overflow:hidden;">
						<img id="wc-cat-banner-crop-img" src="" style="max-width:100%;" />
					</div>
					<p style="margin-top:8px;">
						<button type="button" class="button" id="wc-cat-banner-apply-crop">
							<?php esc_html_e( 'Apply Crop', 'wc-category-banner' ); ?>
						</button>
						<span id="wc-cat-banner-crop-status" style="margin-left:8px;"></span>
					</p>
				</div>

				<div id="wc-cat-banner-cropped-preview" style="<?php echo $cropped_url ? '' : 'display:none;'; ?>margin-bottom:10px;">
					<p><strong><?php esc_html_e( 'Cropped Preview:', 'wc-category-banner' ); ?></strong></p>
					<img id="wc-cat-banner-cropped-img" src="<?php echo esc_url( $cropped_url ); ?>" style="max-width:100%;height:auto;" />
				</div>

				<p>
					<button type="button" class="button" id="wc-cat-banner-upload">
						<?php echo $image_id ? esc_html__( 'Change Banner', 'wc-category-banner' ) : esc_html__( 'Upload Banner', 'wc-category-banner' ); ?>
					</button>
					<button type="button" class="button" id="wc-cat-banner-remove" style="<?php echo $image_id ? '' : 'display:none;'; ?>">
						<?php esc_html_e( 'Remove Banner', 'wc-category-banner' ); ?>
					</button>
				</p>

				<input type="hidden" name="wc_cat_banner_image_id" id="wc-cat-banner-image-id" value="<?php echo esc_attr( $image_id ); ?>" />
				<input type="hidden" name="wc_cat_banner_cropped_id" id="wc-cat-banner-cropped-id" value="<?php echo esc_attr( $cropped_id ); ?>" />
				<input type="hidden" name="wc_cat_banner_crop_data" id="wc-cat-banner-crop-data" value="<?php echo esc_attr( $crop_data ); ?>" />
			</td>
		</tr>

		<tr class="form-field">
			<th scope="row"><label for="wc-cat-banner-position"><?php esc_html_e( 'Banner Position', 'wc-category-banner' ); ?></label></th>
			<td>
				<select name="wc_cat_banner_position" id="wc-cat-banner-position">
					<option value="inside-top" <?php selected( $position, 'inside-top' ); ?>><?php esc_html_e( 'Inside container — Top (above products)', 'wc-category-banner' ); ?></option>
					<option value="inside-bottom" <?php selected( $position, 'inside-bottom' ); ?>><?php esc_html_e( 'Inside container — Bottom (below products)', 'wc-category-banner' ); ?></option>
					<option value="full-width" <?php selected( $position, 'full-width' ); ?>><?php esc_html_e( 'Full page width (outside product container)', 'wc-category-banner' ); ?></option>
				</select>
			</td>
		</tr>

		<tr class="form-field">
			<th scope="row"><label for="wc-cat-banner-crop-mode"><?php esc_html_e( 'Crop Mode', 'wc-category-banner' ); ?></label></th>
			<td>
				<select name="wc_cat_banner_crop_mode" id="wc-cat-banner-crop-mode">
					<option value="auto" <?php selected( $crop_mode, 'auto' ); ?>><?php esc_html_e( 'Automatic (CSS-based responsive fit)', 'wc-category-banner' ); ?></option>
					<option value="manual" <?php selected( $crop_mode, 'manual' ); ?>><?php esc_html_e( 'Manual (crop with visual editor)', 'wc-category-banner' ); ?></option>
				</select>
			</td>
		</tr>

		<tr class="form-field" id="wc-cat-banner-maxheight-field">
			<th scope="row"><label for="wc-cat-banner-max-height"><?php esc_html_e( 'Banner Max Height (px)', 'wc-category-banner' ); ?></label></th>
			<td>
				<input type="number" name="wc_cat_banner_max_height" id="wc-cat-banner-max-height" value="<?php echo esc_attr( $max_height ); ?>" min="0" max="2000" step="10" />
				<p class="description"><?php esc_html_e( 'Maximum banner height in pixels. Used for automatic crop mode. Set 0 for no limit.', 'wc-category-banner' ); ?></p>
			</td>
		</tr>
		<?php
	}

	/* =========================================================================
	   Admin – Save fields
	   ========================================================================= */

	public function save_category_fields( $term_id ) {
		if ( ! isset( $_POST[ self::NONCE_FIELD ] ) || ! wp_verify_nonce( sanitize_text_field( wp_unslash( $_POST[ self::NONCE_FIELD ] ) ), self::NONCE_ACTION ) ) {
			return;
		}
		if ( ! current_user_can( 'manage_woocommerce' ) ) {
			return;
		}

		$image_id   = isset( $_POST['wc_cat_banner_image_id'] ) ? absint( $_POST['wc_cat_banner_image_id'] ) : 0;
		$cropped_id = isset( $_POST['wc_cat_banner_cropped_id'] ) ? absint( $_POST['wc_cat_banner_cropped_id'] ) : 0;
		$position   = isset( $_POST['wc_cat_banner_position'] ) ? sanitize_text_field( wp_unslash( $_POST['wc_cat_banner_position'] ) ) : 'inside-top';
		$crop_mode  = isset( $_POST['wc_cat_banner_crop_mode'] ) ? sanitize_text_field( wp_unslash( $_POST['wc_cat_banner_crop_mode'] ) ) : 'auto';
		$crop_data  = isset( $_POST['wc_cat_banner_crop_data'] ) ? sanitize_text_field( wp_unslash( $_POST['wc_cat_banner_crop_data'] ) ) : '';
		$max_height = isset( $_POST['wc_cat_banner_max_height'] ) ? absint( $_POST['wc_cat_banner_max_height'] ) : 400;

		/* Validate position */
		$allowed_positions = array( 'inside-top', 'inside-bottom', 'full-width' );
		if ( ! in_array( $position, $allowed_positions, true ) ) {
			$position = 'inside-top';
		}

		/* Validate crop mode */
		if ( ! in_array( $crop_mode, array( 'auto', 'manual' ), true ) ) {
			$crop_mode = 'auto';
		}

		update_term_meta( $term_id, self::META_IMAGE_ID, $image_id );
		update_term_meta( $term_id, self::META_POSITION, $position );
		update_term_meta( $term_id, self::META_CROP_MODE, $crop_mode );
		update_term_meta( $term_id, self::META_CROP_DATA, $crop_data );
		update_term_meta( $term_id, self::META_CROPPED_ID, $cropped_id );
		update_term_meta( $term_id, self::META_MAX_HEIGHT, $max_height );
	}

	/* =========================================================================
	   Admin – Enqueue scripts & styles
	   ========================================================================= */

	public function admin_enqueue( $hook ) {
		if ( ! in_array( $hook, array( 'edit-tags.php', 'term.php' ), true ) ) {
			return;
		}
		$screen = get_current_screen();
		if ( ! $screen || 'product_cat' !== $screen->taxonomy ) {
			return;
		}

		wp_enqueue_media();

		/* Cropper.js from CDN */
		wp_enqueue_style(
			'cropperjs',
			'https://cdnjs.cloudflare.com/ajax/libs/cropperjs/1.6.2/cropper.min.css',
			array(),
			'1.6.2'
		);
		wp_enqueue_script(
			'cropperjs',
			'https://cdnjs.cloudflare.com/ajax/libs/cropperjs/1.6.2/cropper.min.js',
			array(),
			'1.6.2',
			true
		);

		/* Inline admin script */
		wp_add_inline_style( 'cropperjs', $this->admin_inline_css() );
		wp_add_inline_script( 'cropperjs', $this->admin_inline_js(), 'after' );

		/* Pass data to JS */
		wp_localize_script( 'cropperjs', 'wcCatBanner', array(
			'ajaxUrl'   => admin_url( 'admin-ajax.php' ),
			'cropNonce' => wp_create_nonce( self::CROP_NONCE ),
		) );
	}

	/* =========================================================================
	   Admin – Inline CSS
	   ========================================================================= */

	private function admin_inline_css() {
		return '
			#wc-cat-banner-wrap .button { margin-right: 5px; }
			#wc-cat-banner-cropper-container { background: #f0f0f0; border: 1px solid #ddd; margin-bottom: 8px; }
			#wc-cat-banner-cropper-container img { display: block; max-width: 100%; }
			#wc-cat-banner-crop-status { font-style: italic; color: #666; }
			#wc-cat-banner-crop-status.success { color: #46b450; font-style: normal; }
			#wc-cat-banner-crop-status.error { color: #dc3232; font-style: normal; }
		';
	}

	/* =========================================================================
	   Admin – Inline JS
	   ========================================================================= */

	private function admin_inline_js() {
		return "
(function(){
	'use strict';

	var imageIdInput, croppedIdInput, cropDataInput,
		preview, previewImg, cropperWrap, cropImg,
		croppedPreview, croppedImg,
		uploadBtn, removeBtn, applyCropBtn, cropStatus,
		cropModeSelect, maxHeightField,
		cropper = null;

	function init() {
		imageIdInput   = document.getElementById('wc-cat-banner-image-id');
		croppedIdInput = document.getElementById('wc-cat-banner-cropped-id');
		cropDataInput  = document.getElementById('wc-cat-banner-crop-data');
		preview        = document.getElementById('wc-cat-banner-preview');
		previewImg     = document.getElementById('wc-cat-banner-img');
		cropperWrap    = document.getElementById('wc-cat-banner-cropper-wrap');
		cropImg        = document.getElementById('wc-cat-banner-crop-img');
		croppedPreview = document.getElementById('wc-cat-banner-cropped-preview');
		croppedImg     = document.getElementById('wc-cat-banner-cropped-img');
		uploadBtn      = document.getElementById('wc-cat-banner-upload');
		removeBtn      = document.getElementById('wc-cat-banner-remove');
		applyCropBtn   = document.getElementById('wc-cat-banner-apply-crop');
		cropStatus     = document.getElementById('wc-cat-banner-crop-status');
		cropModeSelect = document.getElementById('wc-cat-banner-crop-mode');
		maxHeightField = document.getElementById('wc-cat-banner-maxheight-field');

		if ( ! uploadBtn ) return;

		uploadBtn.addEventListener('click', openMedia);
		removeBtn.addEventListener('click', removeBanner);
		applyCropBtn.addEventListener('click', applyCrop);
		cropModeSelect.addEventListener('change', onCropModeChange);

		onCropModeChange();
	}

	function onCropModeChange() {
		var mode = cropModeSelect.value;
		if ( mode === 'manual' && imageIdInput.value && parseInt(imageIdInput.value, 10) > 0 ) {
			showCropper();
			if ( maxHeightField ) maxHeightField.style.display = 'none';
		} else {
			hideCropper();
			if ( maxHeightField ) maxHeightField.style.display = '';
		}
	}

	function openMedia() {
		var frame = wp.media({
			title: 'Select Category Banner',
			button: { text: 'Use as Banner' },
			multiple: false,
			library: { type: 'image' }
		});
		frame.on('select', function(){
			var attachment = frame.state().get('selection').first().toJSON();
			imageIdInput.value = attachment.id;
			croppedIdInput.value = '';
			cropDataInput.value = '';

			var url = attachment.sizes && attachment.sizes.full ? attachment.sizes.full.url : attachment.url;
			previewImg.src = url;
			preview.style.display = '';
			removeBtn.style.display = '';
			uploadBtn.textContent = 'Change Banner';

			croppedPreview.style.display = 'none';
			croppedImg.src = '';
			cropStatus.textContent = '';
			cropStatus.className = '';

			onCropModeChange();
		});
		frame.open();
	}

	function removeBanner() {
		imageIdInput.value = '';
		croppedIdInput.value = '';
		cropDataInput.value = '';
		previewImg.src = '';
		preview.style.display = 'none';
		removeBtn.style.display = 'none';
		uploadBtn.textContent = 'Upload Banner';
		croppedPreview.style.display = 'none';
		croppedImg.src = '';
		hideCropper();
	}

	function showCropper() {
		if ( ! imageIdInput.value || parseInt(imageIdInput.value, 10) < 1 ) return;
		var src = previewImg.src;
		if ( ! src ) return;

		cropImg.src = src;
		cropperWrap.style.display = '';
		preview.style.display = 'none';

		if ( cropper ) {
			cropper.destroy();
			cropper = null;
		}

		cropper = new Cropper(cropImg, {
			viewMode: 1,
			autoCropArea: 1,
			responsive: true,
			restore: false,
			guides: true,
			center: true,
			highlight: true,
			cropBoxMovable: true,
			cropBoxResizable: true,
			toggleDragModeOnDblclick: false,
			ready: function() {
				/* Restore previous crop data if available */
				var saved = cropDataInput.value;
				if ( saved ) {
					try {
						var d = JSON.parse(saved);
						cropper.setData(d);
					} catch(e) {}
				}
			}
		});
	}

	function hideCropper() {
		cropperWrap.style.display = 'none';
		if ( imageIdInput.value && parseInt(imageIdInput.value, 10) > 0 ) {
			preview.style.display = '';
		}
		if ( cropper ) {
			cropper.destroy();
			cropper = null;
		}
	}

	function applyCrop() {
		if ( ! cropper ) return;

		var data = cropper.getData(true);
		cropDataInput.value = JSON.stringify({ x: data.x, y: data.y, width: data.width, height: data.height });
		cropStatus.textContent = 'Cropping...';
		cropStatus.className = '';
		applyCropBtn.disabled = true;

		var fd = new FormData();
		fd.append('action', 'wc_cat_banner_crop');
		fd.append('nonce', wcCatBanner.cropNonce);
		fd.append('image_id', imageIdInput.value);
		fd.append('x', data.x);
		fd.append('y', data.y);
		fd.append('width', data.width);
		fd.append('height', data.height);

		fetch(wcCatBanner.ajaxUrl, { method: 'POST', body: fd, credentials: 'same-origin' })
			.then(function(r){ return r.json(); })
			.then(function(res){
				applyCropBtn.disabled = false;
				if ( res.success ) {
					croppedIdInput.value = res.data.attachment_id;
					croppedImg.src = res.data.url;
					croppedPreview.style.display = '';
					cropStatus.textContent = 'Crop applied successfully!';
					cropStatus.className = 'success';
				} else {
					cropStatus.textContent = res.data || 'Crop failed.';
					cropStatus.className = 'error';
				}
			})
			.catch(function(){
				applyCropBtn.disabled = false;
				cropStatus.textContent = 'Network error. Please try again.';
				cropStatus.className = 'error';
			});
	}

	/* Initialize when DOM is ready */
	if ( document.readyState === 'loading' ) {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
})();
";
	}

	/* =========================================================================
	   AJAX – Server-side image crop
	   ========================================================================= */

	public function ajax_crop_image() {
		check_ajax_referer( self::CROP_NONCE, 'nonce' );

		if ( ! current_user_can( 'manage_woocommerce' ) ) {
			wp_send_json_error( 'Permission denied.' );
		}

		$image_id = isset( $_POST['image_id'] ) ? absint( $_POST['image_id'] ) : 0;
		$x        = isset( $_POST['x'] ) ? intval( $_POST['x'] ) : 0;
		$y        = isset( $_POST['y'] ) ? intval( $_POST['y'] ) : 0;
		$width    = isset( $_POST['width'] ) ? intval( $_POST['width'] ) : 0;
		$height   = isset( $_POST['height'] ) ? intval( $_POST['height'] ) : 0;

		if ( ! $image_id || $width < 1 || $height < 1 ) {
			wp_send_json_error( 'Invalid crop parameters.' );
		}

		$file = get_attached_file( $image_id );
		if ( ! $file || ! file_exists( $file ) ) {
			wp_send_json_error( 'Source image not found.' );
		}

		$editor = wp_get_image_editor( $file );
		if ( is_wp_error( $editor ) ) {
			wp_send_json_error( $editor->get_error_message() );
		}

		$cropped = $editor->crop( $x, $y, $width, $height );
		if ( is_wp_error( $cropped ) ) {
			wp_send_json_error( $cropped->get_error_message() );
		}

		/* Generate a unique filename for the crop */
		$info     = pathinfo( $file );
		$suffix   = "banner-crop-{$x}x{$y}-{$width}x{$height}";
		$new_file = trailingslashit( $info['dirname'] ) . $info['filename'] . '-' . $suffix . '.' . $info['extension'];

		$saved = $editor->save( $new_file );
		if ( is_wp_error( $saved ) ) {
			wp_send_json_error( $saved->get_error_message() );
		}

		/* Create attachment for the cropped image */
		$mime = $saved['mime-type'];
		$attachment = array(
			'post_mime_type' => $mime,
			'post_title'     => sanitize_file_name( $info['filename'] . '-' . $suffix ),
			'post_content'   => '',
			'post_status'    => 'inherit',
		);
		$attach_id = wp_insert_attachment( $attachment, $saved['path'] );

		if ( is_wp_error( $attach_id ) ) {
			wp_send_json_error( 'Could not create attachment.' );
		}

		require_once ABSPATH . 'wp-admin/includes/image.php';
		$metadata = wp_generate_attachment_metadata( $attach_id, $saved['path'] );
		wp_update_attachment_metadata( $attach_id, $metadata );

		wp_send_json_success( array(
			'attachment_id' => $attach_id,
			'url'           => wp_get_attachment_url( $attach_id ),
		) );
	}

	/* =========================================================================
	   Frontend – Get current category banner data
	   ========================================================================= */

	private function get_current_banner_data() {
		if ( ! is_product_category() ) {
			return false;
		}

		$term = get_queried_object();
		if ( ! $term || ! isset( $term->term_id ) ) {
			return false;
		}

		$image_id = absint( get_term_meta( $term->term_id, self::META_IMAGE_ID, true ) );
		if ( ! $image_id ) {
			return false;
		}

		$position   = get_term_meta( $term->term_id, self::META_POSITION, true ) ?: 'inside-top';
		$crop_mode  = get_term_meta( $term->term_id, self::META_CROP_MODE, true ) ?: 'auto';
		$cropped_id = absint( get_term_meta( $term->term_id, self::META_CROPPED_ID, true ) );
		$max_height = get_term_meta( $term->term_id, self::META_MAX_HEIGHT, true );
		$max_height = ( '' === $max_height ) ? 400 : absint( $max_height );

		/* Determine which image to show */
		$display_id = ( 'manual' === $crop_mode && $cropped_id ) ? $cropped_id : $image_id;
		$image_url  = wp_get_attachment_url( $display_id );

		if ( ! $image_url ) {
			return false;
		}

		$alt = get_post_meta( $display_id, '_wp_attachment_image_alt', true );
		if ( ! $alt ) {
			$alt = $term->name . ' banner';
		}

		return array(
			'image_url'  => $image_url,
			'alt'        => $alt,
			'position'   => $position,
			'crop_mode'  => $crop_mode,
			'max_height' => $max_height,
		);
	}

	/* =========================================================================
	   Frontend – Render: Inside Top
	   ========================================================================= */

	public function render_inside_top() {
		$data = $this->get_current_banner_data();
		if ( ! $data || 'inside-top' !== $data['position'] ) {
			return;
		}
		echo $this->build_banner_html( $data, 'wc-cat-banner--inside-top' );
	}

	/* =========================================================================
	   Frontend – Render: Inside Bottom
	   ========================================================================= */

	public function render_inside_bottom() {
		$data = $this->get_current_banner_data();
		if ( ! $data || 'inside-bottom' !== $data['position'] ) {
			return;
		}
		echo $this->build_banner_html( $data, 'wc-cat-banner--inside-bottom' );
	}

	/* =========================================================================
	   Frontend – Render: Full Width
	   ========================================================================= */

	public function render_full_width() {
		$data = $this->get_current_banner_data();
		if ( ! $data || 'full-width' !== $data['position'] ) {
			return;
		}
		echo $this->build_banner_html( $data, 'wc-cat-banner--full-width' );
	}

	/* =========================================================================
	   Frontend – Build banner HTML
	   ========================================================================= */

	private function build_banner_html( $data, $class ) {
		$style = '';
		if ( 'auto' === $data['crop_mode'] && $data['max_height'] > 0 ) {
			$style = ' style="max-height:' . intval( $data['max_height'] ) . 'px;"';
		}

		$html  = '<div class="wc-cat-banner ' . esc_attr( $class ) . '">';
		$html .= '<img src="' . esc_url( $data['image_url'] ) . '" alt="' . esc_attr( $data['alt'] ) . '"' . $style . ' />';
		$html .= '</div>';

		return $html;
	}

	/* =========================================================================
	   Frontend – CSS
	   ========================================================================= */

	public function frontend_css() {
		if ( ! is_product_category() ) {
			return;
		}
		?>
		<style id="wc-cat-banner-css">
			.wc-cat-banner {
				width: 100%;
				overflow: hidden;
				line-height: 0;
				margin-bottom: 20px;
			}
			.wc-cat-banner img {
				display: block;
				width: 100%;
				height: auto;
			}

			/* Inside Top */
			.wc-cat-banner--inside-top {
				margin-bottom: 20px;
			}
			.wc-cat-banner--inside-top img {
				object-fit: cover;
			}

			/* Inside Bottom */
			.wc-cat-banner--inside-bottom {
				margin-top: 20px;
				margin-bottom: 0;
			}
			.wc-cat-banner--inside-bottom img {
				object-fit: cover;
			}

			/* Full Width – break out of any container */
			.wc-cat-banner--full-width {
				width: 100vw !important;
				max-width: 100vw !important;
				position: relative;
				left: 50%;
				right: 50%;
				margin-left: -50vw !important;
				margin-right: -50vw !important;
				margin-bottom: 20px;
			}
			.wc-cat-banner--full-width img {
				width: 100%;
				object-fit: cover;
			}
		</style>
		<?php
	}
}

/* =========================================================================
   Bootstrap
   ========================================================================= */

add_action( 'plugins_loaded', function () {
	if ( class_exists( 'WooCommerce' ) ) {
		WC_Category_Banner::instance();
	}
} );
