/*global europeana, I18n, jQuery, L, RunCoCo */
/*jslint browser: true, nomen: true, white: true */
(function( $ ) {

	'use strict';

	if ( !window.europeana ) {
		window.europeana = {};
	}


	europeana.leaflet = {

		$europeanaCtrls: $('<div>').attr('id', 'europeana-ctrls'),
		googleLayer: {},
		map: {},
		mapLatitude: 0,
		mapLongitude: 0,
		mapQuestAttribution:
			'Tiles © ' +
			'<a href="http://www.mapquest.com/" target="_blank">MapQuest</a> ' +
			'<img src="http://developer.mapquest.com/content/osm/mq_logo.png" />',
		mapQuestLayer: {},
		mapZoom: 8,
		miniMap: {},
		miniMapLayer: {},
		options: {
			banner: {
				content: '',
				display: false,
				position: 'topright'
			},
			europeana_ctrls: true,
			google_layer: true,
			legend: {
				content: '',
				display: false,
				position: 'topright'
			},
			minimap: true,
			zoom_control: {
				display: true,
				position: 'topleft'
			}
		},
		past_collection_day_layer: {},
		upcoming_collection_day_layer: {},


		addBanner: function() {
			if ( !this.options.banner.display ) {
				return;
			}

			var banner = L.control({ position: this.options.banner.position });

			banner.onAdd = function (map) {
				var div = L.DomUtil.create('div', 'banner');
				div.innerHTML = europeana.leaflet.options.banner.content;
				return div;
			};

			banner.addTo( this.map );
		},

		addEuropeanaCtrls: function() {
			if ( !this.options.europeana_ctrls ) {
				return;
			}

			this.$europeanaCtrls.prependTo('#map-container');
			this.$europeanaCtrls.append(
				new europeana.leaflet.EuropeanaLayerControl(
					this.map,
        	[
        		{
        			"title":	I18n.t('javascripts.leaflet.label.map_view'),
        			"layer":	this.mapQuestLayer
        		},
						{
							"title":	I18n.t('javascripts.leaflet.label.satellite_view'),
							"layer":	this.googleLayer
						}
					]
        ).getCmp()
			);
		},

		addGoogleLayer: function() {
			if ( !this.options.google_layer ) {
				return;
			}

			this.googleLayer = new L.Google();
			this.map.addLayer( this.googleLayer );
		},

		addLegend: function() {
			if ( !this.options.legend.display ) {
				return;
			}

			var legend = L.control({ position: this.options.legend.position });

			legend.onAdd = function (map) {
				var div = L.DomUtil.create('div', 'legend');
				div.innerHTML = europeana.leaflet.options.legend.content;
				return div;
			};

			legend.addTo( this.map );
		},

		addMapQuestLayer: function() {
			this.mapQuestLayer = new L.TileLayer(
				'http://otile{s}.mqcdn.com/tiles/1.0.0/{type}/{z}/{x}/{y}.png',
				{
					minZoom: 4,
					maxZoom: 18,
					attribution: this.mapQuestAttribution,
					subdomains: '1234',
					type: 'osm'
				}
			).addTo( this.map );
		},

		addMapZoomControl: function() {
			if ( !this.options.zoom_control.display ) {
				return;
			}

			var zoomControl = new L.Control.Zoom({
				position: this.options.zoom_control.position
			});

			zoomControl.addTo( this.map );
		},

		/**
		 * @param {array} markers
		 * @param {object} markers[n]
		 * @param {array} markers[n].latlng
		 * @param {object|undefined} markers[n].popup
		 * @param {bool|undefined} markers[n].popup.open
		 * @param {string} markers[n].popup.type
		 * @param {string|undefined} markers[n].popup.content
		 */
		addMarkers: function( markers ) {
			if ( markers.length < 1 ) {
				return;
			}

			var
			marker,
			marker_icon = {},
			markers_past = [],
			markers_upcoming = [],
			greenIcon = L.icon({
				iconUrl: '/assets/leaflet/images/marker-icon-green.png'
			}),
			purpleIcon = L.icon({
				iconUrl: '/assets/leaflet/images/marker-icon-purple.png'
			}),
			redIcon = L.icon({
				iconUrl: '/assets/leaflet/images/marker-icon-red.png'
			});

			L.Icon.Default.imagePath = '/assets/leaflet/images/';

			$.each( markers, function() {
				if ( !europeana.leaflet.latLngIsValid( this.latlng ) ) {
					return;
				}

				switch ( this.type ) {
					case 'green':
						marker_icon = { icon: greenIcon };
						break;

					case 'purple':
						marker_icon = { icon: purpleIcon };
						break;

					case 'red':
						marker_icon = { icon: redIcon };
						break;

					default:
						marker_icon = {};
						break;
				}

				marker = L.marker( this.latlng, marker_icon );

				if ( this.popup !== undefined ) {
					if ( this.popup.content !== undefined ) {
						marker.bindPopup( this.popup.content );
					}
				}

				if ( markers.length === 1 ) {
					marker.addTo( europeana.leaflet.map );

					if ( this.popup.open ) {
						marker.openPopup();
					}
				} else if ( this.past ) {
					markers_past.push( marker );
				} else {
					markers_upcoming.push( marker );
				}
			});

			if ( markers_past.length > 0 ) {
				this.past_collection_day_layer = L.layerGroup( markers_past );
				this.map.addLayer( this.past_collection_day_layer );
			}

			if ( markers_upcoming.length > 0 ) {
				this.upcoming_collection_day_layer = L.layerGroup( markers_upcoming );
				this.map.addLayer( this.upcoming_collection_day_layer );
			}
		},

		addMiniMap: function() {
			if ( !this.options.minimap ) {
				return;
			}

			this.miniMapLayer = new L.TileLayer(
				'http://otile{s}.mqcdn.com/tiles/1.0.0/{type}/{z}/{x}/{y}.png',
				{
					minZoom: 0,
					maxZoom: 13,
					attribution: this.mqTilesAttr,
					subdomains: '1234',
					type: 'osm'
				}
			);

			this.miniMap = new L.Control.MiniMap(
				this.miniMapLayer,
				{
					toggleDisplay: true
				}
			);

			this.miniMap.addTo( this.map );
		},

		/**
		 * @param {object} options
		 */
		init: function( options ) {
			if (
				RunCoCo === undefined
				|| RunCoCo.leaflet === undefined
				|| RunCoCo.leaflet.centre === undefined
			) {
				return;
			}

			if ( !this.setMapCentre( RunCoCo.leaflet.centre ) ) {
				return;
			}

			this.options = jQuery.extend( true, {}, this.options, options );

			this.setMapZoom();
			this.setMap();

			if (
				RunCoCo.leaflet.markers !== undefined
				&& $.isArray( RunCoCo.leaflet.markers )
			) {
				this.addMarkers( RunCoCo.leaflet.markers );
			}

			this.addMapQuestLayer();
			this.addGoogleLayer();
			this.addMiniMap();
			this.addMapZoomControl();
			this.addBanner();
			this.addLegend();
			this.addEuropeanaCtrls();
		},

		/**
		 * @param {array} latlng
		 * e.g., [51.5085159,-0.12548849999996037]
		 *
		 * @returns {bool}
		 */
		latLngIsValid: function( latlng ) {
			if (
				!$.isArray( latlng )
				|| latlng.length !== 2
			) {
				return false;
			}

			var regex = /^\s*-?\d+\.\d+\,\s?-?\d+\.\d+\s*$/;

			if ( !latlng.join(',').match( regex ) ) {
				return false;
			}

			return true;
		},

		/**
		 * @param {array} latlng
		 * e.g., [51.5085159,-0.12548849999996037]
		 *
		 * @returns {bool}
		 */
		setMapCentre: function( latlng ) {
			if ( !this.latLngIsValid( latlng ) ) {
				return false;
			}

			this.mapLatitude = parseFloat( latlng[0] );
			this.mapLongitude = parseFloat( latlng[1] );

			return true;
		},

		setMap: function() {
			this.map = L.map(
				'map',
				{
					center: new L.LatLng( this.mapLatitude, this.mapLongitude ),
					zoomControl: false,
					zoom: this.mapZoom,
					scrollWheelZoom: false
				}
			);
		},

		setMapZoom: function() {
			if ( RunCoCo.leaflet.mapZoom === undefined ) {
				return;
			}

			var zoom = parseInt( RunCoCo.leaflet.mapZoom, 10 );

			if ( !$.isNumeric( zoom ) ) {
				return;
			}

			this.mapZoom = zoom;
		},

		EuropeanaLayerControl: function( map, ops ) {
			var
			html	= '',
			layers	= [],
			self = this;

			self.ops = ops;
			self.map = map;
			self.grp = null;

			self._setLayer = function( index ) {
				var layer = self.ops[index].layer;
				self.grp.clearLayers();
				self.grp.addLayer(layer);

				$(self.cmp.find("span")).removeClass('active');
				$(self.cmp.find("span").get(index)).addClass('active');
			};

			$.each( self.ops, function( i, ob ) {
				html += '<a href="#' + ob.title + '"><span class="' + i + '">' + ob.title + '</span></a>';
				layers[layers.length] = ob.layer;
			});

			self.cmp = $('<div>').attr('id', 'layer-ctrl').html( html );

			self.cmp.find("span").each(function(){
				$(this).click( function() {
					if ( $(this).hasClass('active') ) {
						return;
					}
					self._setLayer( parseInt( jQuery(this).attr('class'), 10 ) );
				});
			});

			self.grp = L.layerGroup(layers);
			self.grp.addTo(self.map);
			self._setLayer(0);

			return {
				getCmp : function() {
					return self.cmp;
				}
			};
		}

	};

}( jQuery ));