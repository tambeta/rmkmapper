
var _g = {

	// Marker color, category, star color and text definitions
	// by object type

	markermap : {
		"matkarada" 		: ["#00DF00", "rajad"],
		"õpperada"		 	: ["#00A800", "rajad"],
		"rattarada"		 	: ["#00DFE6", "rajad"],
		"maastikusõidurada"	: ["#2B72C7", "rajad"],

		"puhkekoht"	 		: ["#FFE0C0", "peatuskohad"],
		"lõkkekoht" 		: ["#FF9933", "peatuskohad"],
		"telkimisala" 		: ["#FF9933", "peatuskohad", "#FFDF00"],
		"metsamaja" 		: ["#914700", "peatuskohad"],
		"metsaonn"	 		: ["#4D2600", "peatuskohad"],
		"looduskeskus" 		: ["#FFFF00", "peatuskohad"],
		"teabepunkt" 		: ["#FFFF00", "peatuskohad", null, "i"],
		"vaatetorn"	 		: ["#DC0000", "peatuskohad"],

		"muu"				: ["#CCCCCC", "muu"],
		"_default"			: ["#FFFFFF"]
	},

	map					: null,
	rmk_objects 		: null,
	rmk_tracks			: null,
	infow_last			: null,
	filter_type_map		: {},
	cache_styledicon 	: {}
}

//
// Initialization
//

$(document).ready(function() {

	// Chain asynchronous data loading via jQuery's
	// Deferred / Promise interface.

	var loading_data = $.when(
		//fetch_json("rmk-tracks.json", function(data) { _g.rmk_tracks = data; }),
		fetch_json("rmk.geojson", function(data) { _g.rmk_objects = data.features; })
	);

	_g.map = new google.maps.Map($("#map").get(0), {
		center : new google.maps.LatLng(58.594, 25.016),
		mapTypeId : google.maps.MapTypeId.ROADMAP,
		zoom : 7
	});

	loading_data.done(function() {
		init();
	});
	loading_data.fail(function(jqxhr, textstatus, error) {
		throw new Error("Failed loading JSON data: " + jqxhr.status + "/" + jqxhr.statusText);
	});
});

function init() {

	// Called after document.ready() callback and
	// RMK object data has been fetched and parsed.

	fill_filter();
	check_viewport_size();
	apply_rmk_objects(_g.rmk_objects, _g.map);
	//apply_rmk_tracks(_g.rmk_tracks, _g.map);
	apply_behavior();
}

function apply_behavior() {

	// Apply behavior to UI elements

	// jQuery UI

	$("#accordion")
		.accordion({ fillSpace : true })
		.accordion("activate", 1);
	$("#acc_filter input").button();

	// Filter selection

	$("#acc_filter input:checkbox").change(function() {
		var cb = $(this);
		var type = _g.filter_type_map[cb.attr("id")];
		var show = cb.attr("checked") ? true : false;

		$.each(_g.rmk_objects, function(i, o) {
			var props = o.properties;

			if (props.type != type || !props.marker) return true;
			props.marker.setVisible(show);
		});
	});

	$("#filter_sel_all").click(function() {
		$("#acc_filter input:checkbox")
			.attr("checked", true)
			.button("refresh")
			.change();
	});
	$("#filter_sel_none").click(function() {
		$("#acc_filter input:checkbox")
			.attr("checked", false)
			.button("refresh")
			.change();
	});

	// Compact things for small viewports

	$(window).resize(check_viewport_size);
}

function fill_filter() {

	// Generate contents of the filter pane dynamically

	var div = $("#acc_filter");
	var i = 0;

	$.each(_g.markermap, function(type, v) {
		var row = "";
		var cbid = "cb_filter_" + i;
		var marker;

		if (type == "_default")
			return true;
		marker = new StyledMarker({
			styleIcon : get_styledicon(type)
		});
		_g.filter_type_map[cbid] = type;

		row +=
			"<input type=\"checkbox\" id=\"" + cbid + "\" />" +
			"<label for=\"" + cbid + "\">" + "<img src=\"" + marker.getIcon() + "\" \>&nbsp;" + type + "</label>" +
			"<br/>"
		div.append(row);
		i++;
	});

	div.find(":checkbox").attr("checked", true);
}

//
// Fetching and application of RMK objects
//

function fetch_json(url, cb) {
	return $.get(url, null, function(data, textstatus) {
		if (data) {
			if (typeof(data) == "string") // if sent as text/plain
				data = JSON.parse(data);
			cb.apply(null, [data]);
		}
		else {
			throw new Error("Failed to parse " + url);
		}
	});
}

function apply_rmk_objects(rmk_objects, map) {

	// Apply objects (that are also valid GeoJSON Features) to map. The objects
	// array is modified - Marker and InfoWindow instances are added to each
	// object with coordinates.

	$.each(rmk_objects, function(i, o) {
		var props = o["properties"];
		var coords = o["geometry"]["coordinates"];
		var coord_lon = coords[0];
		var coord_lat = coords[1];

		var marker = props.marker;
		var infow = props.infowindow;
		var regio_href;
		var campicons;

		if (!coord_lat || !coord_lon)
			return true;

		if (!marker) {
			marker = new StyledMarker({
				styleIcon : get_styledicon(props.type),
				position : new google.maps.LatLng(coord_lat, coord_lon),
				map : map
			});
			props.marker = marker;
		}

		if (!infow) {
			campicons =
				"<div class=\"campicons\">" +
				(props.has_tenting ?
					"<img src=\"ui/img/icon-tent-32.png\" alt=\"Telkimine\"" +
					"title=\"Telkimisvõimalus\" />" : "") +
				(props.has_firesite ?
					"<img src=\"ui/img/icon-campfire-32.png\" alt=\"Lõkkekoht\"" +
					"title=\"Kattega lõkkekoht\" />" : "") +
				"</div>";
			regio_href =
				"http://kaart.otsing.delfi.ee/index.php?id=1&bbox=" +
				props.coord_x + "," + props.coord_y + "," + props.coord_x + "," + props.coord_y;
			infow = new google.maps.InfoWindow({
				content :
					"<div class=\"iwcontent\">" +
					"<b>" + props.name + "</b><ul>" +
					(props.location  ? "<li>" + props.location  + "</li>" : "") +
					(props.equipment ? "<li>" + props.equipment + "</li>" : "") +
					(props.sights    ? "<li>" + props.sights    + "</li>" : "") +
					"</ul><a href=\"" + props.href + "\">RMK</a>" + " | " +
					"<a href=\"" + regio_href + "\">Regio atlas</a>" +
					campicons + "</div>"
			});
			google.maps.event.addListener(marker, 'click', function() {
				if (_g.infow_last)
					_g.infow_last.close();
				infow.open(map, marker);
				_g.infow_last = infow;
			});
			props.infowindow = infow;
		}
	});
}

function apply_rmk_tracks(rmk_tracks, map) {
	$.each(rmk_tracks, function(i, o) {
		var path = [];
		var polyline;
		var infow;
		var anch;

		$.each(o.waypoints, function(i, ll) {
			path.push(new google.maps.LatLng(ll[0], ll[1]));
		});

		polyline = new google.maps.Polyline({
			path : path,
			map : map,
			strokeColor: "#37A42C",
			strokeOpacity: 0.6,
		});
		infow = new google.maps.InfoWindow({
			content :
				"<div class=\"iwcontent\">" +
				"<b>" + o.name + " rada</b><ul>" +
				"</div>"
		});
		anch = new google.maps.MVCObject;

		google.maps.event.addListener(polyline, 'click', function(e) {
			anch.set("position", e.latLng);
			if (_g.infow_last)
				_g.infow_last.close();
			infow.open(map, anch);
			_g.infow_last = infow;
		});

		o.polyline = polyline;
	});
}

//
// Utility functions
//

function check_viewport_size() {
	if ($(window).width() < 1160) {
		$("#acc_filter").css("padding", "0.5em");
	}
	else {
		$("#acc_filter").css("padding", "");
	}

	if ($(window).width() > 1400) {
		$("body").css("padding-left", "4em");
		$("body").css("padding-right", "4em");
	}
	else {
		$("body").css("padding-left", "");
		$("body").css("padding-right", "");
	}
}

function get_styledicon(type) {

	// Return a new StyledIcon based on object type.
	// Generated icons are cached.

	var color 		= _g.markermap[type][0] || _g.markermap["_default"][0];
	var starcolor	= _g.markermap[type][2] || "";
	var text		= _g.markermap[type][3] || "";
	var si			= _g.cache_styledicon[type];

	if (si) return si;

	si = new StyledIcon(
		text ? StyledIconTypes.BUBBLE : StyledIconTypes.MARKER,
		{color : color, starcolor : starcolor, text : text}
	);
	_g.cache_styledicon[type] = si;
	return si;
}

