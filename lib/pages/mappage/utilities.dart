import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:wasabee/pages/mappage/markerutilities.dart';
import 'package:wasabee/network/responses/operationFullResponse.dart';
import '../../classutils/target.dart';
import 'dart:async';
import 'dart:ui' as ui;

class MapUtilities {
  static const ZOOM_LEVEL_DIFF_CONST = 1.46661;

  static double getViewCircleZoomLevel(
      LatLng center, LatLngBounds bounds, bool fromExistingLocation) {
    Circle circle = Circle(
        center: center, radius: calculateDistance(bounds), circleId: null);
    return getZoomLevel(circle, fromExistingLocation);
  }

  static double calculateDistance(LatLngBounds bounds) {
    var lat1 = bounds.southwest.latitude;
    var lon1 = bounds.southwest.longitude;
    var lat2 = bounds.northeast.latitude;
    var lon2 = bounds.northeast.longitude;
    var earthRadiusKm = 6371;
    var dLat = radians(lat2 - lat1);
    var dLon = radians(lon2 - lon1);

    lat1 = radians(lat1);
    lat2 = radians(lat2);

    var a = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));
    var distance = earthRadiusKm * c * 1000;
    return distance;
  }

  static double getPortalLevel(double distance,
      {int agents = 0, bool allowMods}) {
    if (distance < 160.0) {
      return 1.0;
    }
    if (distance > 6553000.0) {
      // link amp required
      return 8.0;
    }
    return (getRoot(distance, 4)) / (2 * getRoot(10, 4));
  }

  static double getRoot(double base, int n) {
    return pow(e, log(base) / n);
  }

  static double getZoomLevel(Circle circle, bool fromExistingLocation) {
    double zoomlevel = 14.0;
    if (circle != null) {
      double radius = circle.radius;
      double scale = radius / 500;
      zoomlevel = (16 - log(scale) / log(2));
    }
    //_visibleRegion isn't exact, zoom level zooms out a bit each time, not sure why.
    //But, it's diff by the same amount each time, so this const fixes it for now.
    if (fromExistingLocation) zoomlevel = zoomlevel + ZOOM_LEVEL_DIFF_CONST;
    return zoomlevel;
  }

  static List<LatLng> getLatLngListFromMarkers(List<Marker> markers) {
    var list = List<LatLng>();
    for (var marker in markers) {
      if (!marker.markerId.value.startsWith("agent_"))
        list.add(marker.position);
    }
    return list;
  }

  static LatLng computeCentroid(List<LatLng> markers) {
    double latitude = 0;
    double longitude = 0;

    var listToAverage = List<LatLng>();
    listToAverage.add(getSouthWest(markers));
    listToAverage.add(getNorthEast(markers));
    for (LatLng point in listToAverage) {
      latitude += point.latitude;
      longitude += point.longitude;
    }

    return new LatLng(
        latitude / listToAverage.length, longitude / listToAverage.length);
  }

  static LatLngBounds getBounds(List<LatLng> markers) {
    return new LatLngBounds(
        northeast: getNorthEast(markers), southwest: getSouthWest(markers));
  }

  static LatLng getNorthEast(List<LatLng> markers) {
    double finalLat = 0;
    double finalLon = 0;
    for (var marker in markers) {
      if (finalLat == 0)
        finalLat = marker.latitude;
      else if (marker.latitude > finalLat) finalLat = marker.latitude;

      if (finalLon == 0)
        finalLon = marker.longitude;
      else if (marker.longitude > finalLon) finalLon = marker.longitude;
    }
    return LatLng(finalLat, finalLon);
  }

  static LatLng getSouthWest(List<LatLng> markers) {
    double finalLat = 0;
    double finalLon = 0;

    for (var marker in markers) {
      if (finalLat == 0)
        finalLat = marker.latitude;
      else if (marker.latitude < finalLat) finalLat = marker.latitude;

      if (finalLon == 0)
        finalLon = marker.longitude;
      else if (marker.longitude < finalLon) finalLon = marker.longitude;
    }
    return LatLng(finalLat, finalLon);
  }

  static LatLng getCenterFromBounds(LatLngBounds bounds) {
    var northEastLon = bounds.northeast.longitude;
    var northEastLat = bounds.northeast.latitude;
    var southWestLon = bounds.southwest.longitude;
    var southWestLat = bounds.southwest.latitude;

    if ((southWestLon - northEastLon > 180) ||
        (northEastLon - southWestLon > 180)) {
      southWestLon += 360;
      southWestLon %= 360;
      northEastLon += 360;
      northEastLon %= 360;
    }
    var centerLat = (southWestLat + northEastLat) / 2;
    var centerLng = (southWestLon + northEastLon) / 2;
    return LatLng(centerLat, centerLng);
  }

  static launchMaps(LatLng location, String label) async {
    String googleUrl =
        'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}';
    String appleUrl =
        'https://maps.apple.com/?ll=${location.latitude},${location.longitude}&q=${Uri.encodeFull(label)}';
    if (Platform.isIOS) {
      print('$appleUrl');
      if (await canLaunch(appleUrl)) {
        await launch(appleUrl);
      } else if (await canLaunch(googleUrl)) {
        await launch(googleUrl);
      }
    } else {
      if (await canLaunch(googleUrl)) {
        await launch(googleUrl);
      }
    }
  }
}

class HexColor extends Color {
  static int _getColorFromHex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF" + hexColor;
    }
    return int.parse(hexColor, radix: 16);
  }

  HexColor(final String hexColor) : super(_getColorFromHex(hexColor));
}

class MapMarkerBitmapBank {
  Map<String, BitmapDescriptor> bank = Map();

  Future<BitmapDescriptor> getIconFromBank(
      String key, BuildContext context, Target target, String googleId) async {
    BitmapDescriptor bmd = bank[key];
    if (bmd != null) {
      return bmd;
    } else {
      ImageConfiguration imageConfiguration =
          createLocalImageConfiguration(context, size: Size(5, 3));
      if (key.startsWith("agent_")) {
        bmd = await getAgentImage(key, imageConfiguration, context);
      } else {
        var path = getPathFromKey(key, target, googleId);
        if (target != null) key = path;
        bmd = BitmapDescriptor.fromBytes(await getBytesFromAsset(path, 35));
        // bmd = await BitmapDescriptor.fromAssetImage(imageConfiguration, path);
      }
      bank[key] = bmd;
      return bmd;
    }
  }

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))
        .buffer
        .asUint8List();
  }

  Future<BitmapDescriptor> getAgentImage(String key,
      ImageConfiguration imageConfiguration, BuildContext context) async {
    print('getting backup agent image');
    return await BitmapDescriptor.fromAssetImage(
        imageConfiguration, 'assets/icons/avatar_placeholder.bmp');
  }

/*
  Future<BitmapDescriptor> getIconFromUrl(
      String url, ImageConfiguration configuration) async {
    final Completer<BitmapDescriptor> bitmapIcon =
        Completer<BitmapDescriptor>();

    Image.network(url)
        .image
        .resolve(configuration)
        .addListener(ImageStreamListener((ImageInfo image, bool sync) async {
      final ByteData bytes =
          await image.image.toByteData(format: ImageByteFormat.png);
      final BitmapDescriptor bitmap =
          BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
      bitmapIcon.complete(bitmap);
    }));

    return await bitmapIcon.future;
  }
  */

  String getPathFromKey(String key, Target target, String googleId) {
    String path = 'assets/icons/unknown.bmp';
    switch (key) {
      case TargetUtils.LetDecayPortalAlert:
      case TargetUtils.DestroyPortalAlert:
      case TargetUtils.UseVirusPortalAlert:
      case TargetUtils.GetKeyPortalAlert:
      case TargetUtils.LinkPortalAlert:
      case TargetUtils.MeetAgentPortalAlert:
      case TargetUtils.OtherPortalAlert:
      case TargetUtils.RechargePortalAlert:
      case TargetUtils.UpgradePortalAlert:
      case TargetUtils.GotoPortalMarker:
      case TargetUtils.FarmPortalMarker:
        path =
            "assets/markers/${MarkerUtilities.getImagePath(target, googleId, MarkerUtilities.SEGMENT_MARKER)}";
        break;
      case "groupa":
        path = 'assets/icons/groupa_2.bmp';
        break;
      case "groupb":
        path = 'assets/icons/groupb.bmp';
        break;
      case "groupc":
        path = 'assets/icons/groupc.bmp';
        break;
      case "groupd":
        path = 'assets/icons/groupd.bmp';
        break;
      case "groupe":
        path = 'assets/icons/groupe.bmp';
        break;
      case "groupf":
        path = 'assets/icons/groupf.bmp';
        break;
    }
    return path;
  }
}
