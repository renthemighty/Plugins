
jQuery(document).ready(function() {

	checkVisible();
	checkFreeProduct();
	jQuery("#selFreeProduct").select2();
});

function checkVisible() {
	
	if(jQuery('#chkEnableMinCartAmt:checked').length > 0) {
		jQuery('#trMinCart').show(400);
	} else {
		jQuery('#trMinCart').hide(200);
	}
}

function checkFreeProduct() {

	if(jQuery('#rdoFreeProduct:checked').length > 0) {
		jQuery('#trFreeProduct').show(400);
		jQuery('#trDiscountValue').hide();
	} else if(jQuery('#rdoFreeShipping:checked').length > 0){
		jQuery('#trDiscountValue').hide(400);
		jQuery('#trFreeProduct').hide();
	} else {
		jQuery('#trDiscountValue').show(400);
		jQuery('#trFreeProduct').hide();
	}
}