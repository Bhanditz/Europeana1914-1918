(function() {
	
	'use strict';
	
	var $navigation_mobile = jQuery('#navigation-mobile'),
			$navigation_user = jQuery('#navigation-user'),
			$navigation_main = jQuery('#navigation-main');
	
	
	$.fn.fadeSlideToggle = function(speed, fn) {
		
		return $(this).animate({
			'height': 'toggle',
			'opacity': 'toggle'
		}, speed || 400, function() {
			$.isFunction(fn) && fn.call(this);
		});
		
	};
	
	
	function handleClick( evt ) {
		
		evt.preventDefault();
		evt.stopPropagation();
		
		
		if ( jQuery(window).width() >= 768 ) {
			
			if ( !$navigation_user.is(':visible') ) {
				
				$navigation_user.add( $navigation_main ).fadeSlideToggle(500);
				
			}
			
			return;
			
		}
		
		if ( this.id === 'navigation-mobile' ) {
			
			if ( !$navigation_user.is(':visible') ) {
				
				$navigation_user.add( $navigation_main ).fadeSlideToggle(500);
				$navigation_mobile.fadeToggle();
				
			}
			
		} else {
			
			if ( $navigation_user.is(':visible') ) {
				
				$navigation_user.add( $navigation_main ).fadeSlideToggle(500);
				$navigation_mobile.fadeToggle();
				
			}
			
		}
		
	}
	
	$navigation_mobile.add(document).on('click', handleClick);
	
}());