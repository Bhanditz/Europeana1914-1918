/*global europeana, I18n, jQuery */
/*jslint browser: true, white: true */
(function($ ) {

	'use strict';

	var
	chosen = {
		/**
		 * @param {Event} arguments[0]
		 * jQuery Event
		 *
		 * @param {object} arguments[1]
		 * @param {string} arguments[1].selected
		 */
		handleChange: function() {
			if (
				arguments[1] === undefined ||
				arguments[1].selected === undefined
			) {
				return;
			}

			var pieces = arguments[1].selected.split('|');

			if ( pieces.length === 2 && pieces[1] === 'searchable' ) {
				window.location.href =
					window.location.protocol + "//" +
					window.location.host + "/" +
					'collection/explore/collection_day/' +
					pieces[0] +
					'?qf[index]=c';
			} else {
				window.location.href =
					window.location.protocol + "//" +
					window.location.host + "/" +
					'collection-days/' +
					arguments[1].selected;
			}
		},

		init: function() {
			$('.chosen-select').chosen().change( this.handleChange );
		}
	},

	leaflet = {
		banner_content: '',
		legend_content: '',

		init: function() {
			this.setLegendContent();
			this.setBannerContent();
			this.setUpLeaflet();
		},

		setBannerContent: function() {
			if (
				!$.isArray( RunCoCo.leaflet.upcoming ) ||
				RunCoCo.leaflet.upcoming.length < 1
			) {
				return;
			}

			var
			upcoming_day = RunCoCo.leaflet.upcoming[0],
			upcoming_values = {
				"name": upcoming_day.name ? upcoming_day.name : '',
				"city": upcoming_day.city ? upcoming_day.city: '',
				"country": upcoming_day.country ? upcoming_day.country : '',
				"start-date": upcoming_day.date ? upcoming_day.date : ''
			};

			this.banner_content =
				I18n.t(
					'javascripts.collection-days.next-collection-day',
					upcoming_values
				) +
				' ' +
				'<a href="collection-days/' + RunCoCo.leaflet.upcoming[0].code + '">' +
					I18n.t( 'javascripts.collection-days.find-more' ) +
				'</a>';
		},

		setLegendContent: function() {
			this.legend_content =
				'<h2>' + I18n.t( 'javascripts.collection-days.legend' ) + '</h2>' +
				'<div class="marker-icon marker-icon-green">' + I18n.t( 'javascripts.collection-days.upcoming' ) + '</div>' +
				'<div class="marker-icon marker-icon-red">' + I18n.t( 'javascripts.collection-days.past-entered' ) + '</div>' +
				'<div class="marker-icon marker-icon-purple">' + I18n.t( 'javascripts.collection-days.past-not-entered' ) + '</div>' +
				'<label><input type="checkbox" /> ' + I18n.t( 'javascripts.collection-days.show-past' ) + '</label>' +
				'<a href="#what-is-it">' + I18n.t( 'javascripts.collection-days.what-is-it' ) + '</a>';
		},

		setUpLeaflet: function() {
			europeana.leaflet.init({
				banner: {
					display: true,
					content: this.banner_content
				},
				legend: {
					display: true,
					content: this.legend_content
				},
				zoom_control: {
					position: 'bottomleft'
				}
			});
		}
	};

	chosen.init();
	leaflet.init();

}( jQuery ));