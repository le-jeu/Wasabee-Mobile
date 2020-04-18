import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wasabee/classutils/link.dart';
import 'package:wasabee/classutils/operation.dart';
import 'package:wasabee/classutils/target.dart';
import 'package:wasabee/main.dart';
import 'package:wasabee/network/responses/meResponse.dart';
import 'package:flutter/foundation.dart';
import 'package:wasabee/network/responses/operationFullResponse.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wasabee/pages/alertspage/alertfiltermanager.dart';
import 'package:wasabee/pages/alertspage/alerts.dart';
import 'package:wasabee/pages/alertspage/alertsortdialog.dart';
import 'package:wasabee/pages/alertspage/targetlistvm.dart';
import 'package:wasabee/pages/linkspage/linkfiltermanager.dart';
import 'package:wasabee/pages/linkspage/linklistvm.dart';
import 'package:wasabee/pages/linkspage/links.dart';
import 'package:wasabee/pages/linkspage/linksortdialog.dart';
import 'package:wasabee/pages/loginpage/login.dart';
import 'package:wasabee/pages/mappage/mapview.dart';
import 'package:wasabee/pages/settingspage/constants.dart';
import 'package:wasabee/pages/settingspage/settings.dart';
import 'package:wasabee/pages/teamspage/team.dart';
import '../../location/locationhelper.dart';
import '../../network/networkcalls.dart';
import '../../network/urlmanager.dart';
import '../../storage/localstorage.dart';
import '../../pages/mappage/utilities.dart';
import '../../network/responses/teamsResponse.dart';
import 'dart:convert';

class MapPage extends StatefulWidget {
  final List<Op> ops;
  final String googleId;
  final AlertFilterType alertFilterDropdownValue;
  final AlertSortType alertSortDropdownValue;
  final LinkFilterType linkFilterDropdownValue;
  final LinkSortType linkSortDropDownValue;
  final bool useImperialUnitsValue;
  MapPage(
      {Key key,
      @required this.ops,
      this.googleId,
      this.alertFilterDropdownValue,
      this.alertSortDropdownValue,
      this.linkFilterDropdownValue,
      this.linkSortDropDownValue,
      this.useImperialUnitsValue})
      : super(key: key);

  @override
  MapPageState createState() => MapPageState(
      ops,
      googleId,
      alertFilterDropdownValue,
      alertSortDropdownValue,
      linkFilterDropdownValue,
      linkSortDropDownValue,
      useImperialUnitsValue);
}

class MapPageState extends State<MapPage> with SingleTickerProviderStateMixin {
  static const ZOOMED_ZOOM_LEVEL = 18.0;
  var firstLoad = true;
  var isLoading = true;
  var sharingLocation = false;
  var pendingGrab;
  Op selectedOperation;
  String googleId;
  LatLng mostRecentLoc;
  AlertFilterType alertFilterDropdownValue;
  AlertSortType alertSortDropdownValue;
  LinkFilterType linkFilterDropdownValue;
  LinkSortType linkSortDropDownValue;
  bool useImperialUnitsValue;
  Operation loadedOperation;
  GoogleMapController mapController;
  List<Op> operationList = List();
  Map<MarkerId, Marker> markers = <MarkerId, Marker>{};
  Map<PolylineId, Polyline> polylines = <PolylineId, Polyline>{};
  Map<MarkerId, Marker> targets = <MarkerId, Marker>{};
  MapMarkerBitmapBank bitmapBank = MapMarkerBitmapBank();
  LatLngBounds _visibleRegion;
  TabController tabController;
  final List<Tab> myTabs = <Tab>[
    Tab(text: 'Map'),
    Tab(text: 'Alerts'),
    Tab(text: 'Links'),
  ];

  MapPageState(
      List<Op> ops,
      googleId,
      alertFilterDropdownValue,
      alertSortDropdownValue,
      linkFilterDropdownValue,
      linkSortDropDownValue,
      useImperialUnitsValue) {
    this.operationList = ops;
    this.googleId = googleId;
    this.alertFilterDropdownValue = alertFilterDropdownValue;
    this.alertSortDropdownValue = alertSortDropdownValue;
    this.linkFilterDropdownValue = linkFilterDropdownValue;
    this.linkSortDropDownValue = linkSortDropDownValue;
    this.useImperialUnitsValue = useImperialUnitsValue;
  }

  @override
  void initState() {
    LocalStorageUtils.getIsLocationSharing().then((bool isLocationSharing) {
      sharingLocation = isLocationSharing;
      sendLocationIfSharing();
    });
    tabController = new TabController(vsync: this, length: myTabs.length);
    WidgetsBinding.instance.addPostFrameCallback((_) => doInitialLoadThings());
    super.initState();
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: getPageContent(),
      builder: (BuildContext context, AsyncSnapshot<Widget> snapshot) {
        if (snapshot.hasData) {
          return snapshot.data;
        } else {
          return getLoadingView();
        }
      },
    );
  }

  Widget getLoadingView() {
    return Container(
        color: Colors.white,
        child: Center(
          child: CircularProgressIndicator(),
        ));
  }

  Future<Widget> getPageContent() async {
    print("Operation -> ${loadedOperation.toJson()}");
    return isLoading
        ? getLoadingView()
        : Scaffold(
            appBar: AppBar(
              bottom: TabBar(
                controller: tabController,
                tabs: myTabs,
              ),
              title: Text(selectedOperation == null
                  ? 'Wasabee - Map'
                  : '${selectedOperation.name}'),
              actions: loadedOperation == null
                  ? null
                  : <Widget>[
                      IconButton(
                        icon: Icon(Icons.settings),
                        onPressed: () {
                          pressedSettings();
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh),
                        onPressed: () {
                          doRefresh(selectedOperation, true);
                        },
                      )
                    ],
            ),
            body: TabBarView(
              controller: tabController,
              physics: NeverScrollableScrollPhysics(),
              children: [
                isLoading
                    ? getLoadingView()
                    : MapViewWidget(
                        mapPageState: this,
                        markers: markers,
                        polylines: polylines,
                        visibleRegion: _visibleRegion),
                isLoading
                    ? getLoadingView()
                    : AlertsPage.getPageContent(
                        await TargetListViewModel.fromOperationData(
                            alertFilterDropdownValue != null
                                ? TargetUtils.getFilteredMarkers(
                                    loadedOperation.markers,
                                    alertFilterDropdownValue,
                                    googleId)
                                : loadedOperation.markers,
                            OperationUtils.getPortalMap(
                                loadedOperation.opportals),
                            googleId,
                            mostRecentLoc,
                            alertSortDropdownValue,
                            useImperialUnitsValue),
                        loadedOperation.markers,
                        this),
                isLoading
                    ? getLoadingView()
                    : LinksPage.getPageContent(
                        await LinkListViewModel.fromOperationData(
                            linkFilterDropdownValue != null
                                ? LinkUtils.getFilteredLinks(
                                    loadedOperation.links,
                                    linkFilterDropdownValue,
                                    googleId)
                                : loadedOperation.markers,
                            OperationUtils.getPortalMap(
                                loadedOperation.opportals),
                            googleId,
                            linkSortDropDownValue,
                            useImperialUnitsValue,
                            selectedOperation.iD),
                        loadedOperation.links,
                        this),
              ],
            ),
            drawer: isLoading
                ? null
                : Drawer(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: getDrawerElements(),
                    ),
                  ),
          );
  }

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  updateVisibleRegion() async {
    if (mapController != null) {
      final LatLngBounds visibleRegion = await mapController.getVisibleRegion();
      _visibleRegion = visibleRegion;
    }
  }

  List<Widget> getDrawerElements() {
    if (operationList == null || operationList.isEmpty) {
      return <Widget>[
        DrawerHeader(
          child: Text(
            'Wasabee Operations',
            style: TextStyle(color: Colors.white, fontSize: 25.0),
          ),
          decoration: BoxDecoration(
            color: Colors.green,
          ),
        ),
      ];
    } else {
      var listOfElements = List<Widget>();
      listOfElements.add(getDrawerHeader());
      listOfElements.add(getShareLocationViews());
      listOfElements.add(getRefreshOpListButton());
      listOfElements.add(getEditTeamsButton());
      for (var op in operationList) {
        listOfElements.add(ListTile(
          title: Text(op.name),
          selected: op.isSelected,
          onTap: () {
            tappedOp(op, operationList);
            Navigator.pop(context);
          },
        ));
      }
      return listOfElements;
    }
  }

  Widget getDrawerHeader() {
    return DrawerHeader(
      child: Column(
        children: <Widget>[
          Text(
            'Wasabee Operations',
            style: TextStyle(color: Colors.white, fontSize: 25.0),
          ),
          Center(
            child: Container(
                margin: const EdgeInsets.all(10),
                child: CircleAvatar(
                  radius: 40.0,
                  backgroundColor: Colors.white,
                  child: new Image.asset(
                    'assets/images/wasabee.png',
                    width: 70.0,
                    height: 70.0,
                    fit: BoxFit.cover,
                  ),
                )),
          )
        ],
      ),
      decoration: BoxDecoration(
        color: Colors.green,
      ),
    );
  }

  Widget getShareLocationViews() {
    return Center(
        child: Container(
            color: Colors.grey[200],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  "Sharing Location",
                  style: TextStyle(color: Colors.black),
                ),
                Checkbox(
                  value: sharingLocation,
                  onChanged: (value) {
                    setState(() {
                      print('VALUE -> $value');
                      LocalStorageUtils.storeIsLocationSharing(value)
                          .then((any) {
                        sendLocationIfSharing();
                      });
                      sharingLocation = value;
                    });
                  },
                )
              ],
            )));
  }

  Widget getRefreshOpListButton() {
    return Container(
        margin: EdgeInsets.fromLTRB(10, 0, 10, 0),
        child: RaisedButton(
          color: Colors.green,
          child: Text(
            'Refresh Op List',
            style: TextStyle(color: Colors.white),
          ),
          onPressed: () {
            tappedRefreshAllOps(true);
          },
        ));
  }

  Widget getEditTeamsButton() {
    return Container(
        margin: EdgeInsets.fromLTRB(10, 0, 10, 0),
        child: RaisedButton(
          color: Colors.green,
          child: Text(
            'Manage My Teams',
            style: TextStyle(color: Colors.white),
          ),
          onPressed: () {
            LocalStorageUtils.getTeamSort().then((sortValue) {
              LocalStorageUtils.getTeamFilter().then((filterValue) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) {
                    return TeamPage(
                        teamSortDropDownValue: sortValue,
                        teamFilterDropDownValue: filterValue,
                        googleId: googleId);
                  }),
                ).then((onValue) {
                  if (onValue) {
                    tappedRefreshAllOps(false);
                  }
                  print('returned settings with -> $onValue');
                });
              });
            });
          },
        ));
  }

  sendLocationIfSharing() {
    if (sharingLocation) {
      LocationHelper.locateUser().then((Position userPosition) {
        if (userPosition != null) {
          try {
            var url =
                "${UrlManager.FULL_LAT_LNG_URL}lat=${userPosition.latitude}&lon=${userPosition.longitude}";
            NetworkCalls.doNetworkCall(url, Map<String, String>(), gotLocation,
                false, NetWorkCallType.GET, null);
          } catch (e) {
            print(e);
          }
        }
      });
    }
  }

  gotLocation(String response, dynamic object) {
    print("gotLocation -> $response");
  }

  tappedRefreshAllOps(bool shouldShowDialog) {
    if (shouldShowDialog)
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return OperationUtils.getRefreshOpListDialog(context);
        },
      );
    else
      Navigator.pushNamedAndRemoveUntil(
          context, WasabeeConstants.LOGIN_ROUTE_NAME, (r) => false);
  }

  doRefresh(Op op, bool resetVisibleRegion) async {
    if (resetVisibleRegion) _visibleRegion = null;
    setState(() {
      doSelectOperationThing(op);
      pendingGrab = op;
    });
  }

  doSelectOperationThing(Op operation) {
    print('setting pending grab');
    operation.isSelected = true;
    this.pendingGrab = operation;
    this.selectedOperation = operation;
    if (pendingGrab != null) getFullOperation(pendingGrab);
  }

  doInitialLoadThings() async {
    if (operationList != null && operationList.length > 0) {
      var foundOperation = await checkForSelectedOp(operationList);
      if (foundOperation == null) {
        print('FOUND operation is null!');
        doSelectOperationThing(operationList.first);
      } else {
        doSelectOperationThing(foundOperation);
      }
    } else {
      var dialog = OperationUtils.getNoOperationDialog(context);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return dialog;
        },
      );
    }
  }

  Future<Op> checkForSelectedOp(List<Op> operationList) async {
    var selectedOpId = await LocalStorageUtils.getSelectedOpId();
    if (selectedOpId != null) {
      Op foundOperation;
      for (var listOp in operationList) {
        if (listOp.iD == selectedOpId) foundOperation = listOp;
      }

      return foundOperation;
    } else {
      return null;
    }
  }

  getFullOperation(Op op) async {
    isLoading = true;
    pendingGrab = null;
    try {
      var url = "${UrlManager.FULL_OPERATION_URL}${op.iD}";
      NetworkCalls.doNetworkCall(url, Map<String, String>(), gotOperation,
          false, NetWorkCallType.GET, null);
    } catch (e) {
      setIsNotLoading();
      print(e);
    }
  }

  gotOperation(String response, dynamic object) async {
    print('got operation! -> $response');
    try {
      var operation = Operation.fromJson(json.decode(response));
      if (operation != null) {
        loadedOperation = operation;
        Position recentPosition;
        if (await Permission.location.request().isGranted) {
          print('permission was granted');
          recentPosition = await LocationHelper.locateUser();
          mostRecentLoc =
              LatLng(recentPosition.latitude, recentPosition.longitude);
        } else
          print('Permission was denied');

        await populateEverything();
        var url = "${UrlManager.FULL_GET_TEAM_URL}${selectedOperation.teamID}";
        NetworkCalls.doNetworkCall(url, Map<String, String>(), gotTeam, false,
            NetWorkCallType.GET, null);
      } else {
        print("operation is null");
        parsingOperationFailed();
      }
    } catch (e) {
      print('Failed get op -> $e');
      parsingOperationFailed();
      setIsNotLoading();
    }
  }

  populateEverything() async {
    print('populatingEverything -> ${loadedOperation.toJson()}');
    try {
      markers.clear();
      polylines.clear();
      await populateBank();
      bitmapBank.bank.clear();
      await populateAnchors(loadedOperation);
      await populateLinks(loadedOperation);
      await populateTargets(loadedOperation);
    } catch (e) {
      print("Exception In populateEverything -> $e");
    }
    print('finished populating');
  }

  finishedTargetActionCall(String response, dynamic object) {
    doRefresh(selectedOperation, false);
    //gotOperation(response);
  }

  gotTeam(String response, dynamic object) {
    try {
      var team = FullTeam.fromJson(json.decode(response));
      populateTeamMembers(team.agents);
      setIsNotLoading();
      if (loadedOperation != null) {
        var dialogToShow =
            OperationUtils.checkForAlertsMarkersLinks(loadedOperation, context);
        if (dialogToShow != null)
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return dialogToShow;
            },
          );
      }
    } catch (e) {
      NetworkCalls.checkNetworkException(e, context);
    }
  }

  parsingOperationFailed() async {
    var operationName =
        selectedOperation != null ? " '${selectedOperation.name}'" : "";
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return OperationUtils.getParsingOperationFailedDialog(
            context, operationName);
      },
    );
  }

  populateTargets(Operation operation) async {
    if (operation?.markers != null) {
      populateBank();
      for (var target in operation.markers) {
        final MarkerId targetId = MarkerId(target.iD);
        final Portal portal =
            OperationUtils.getPortalFromID(target.portalId, operation);
        if (portal != null) {
          final Marker marker = Marker(
              markerId: targetId,
              icon: await bitmapBank.getIconFromBank(
                  target.type, context, target, googleId),
              position: LatLng(
                double.parse(portal.lat),
                double.parse(portal.lng),
              ),
              infoWindow: InfoWindow(
                title: portal.name,
                snippet: TargetUtils.getMarkerTitle(portal.name, target),
                onTap: () {
                  _onTargetInfoWindowTapped(target, portal, targetId);
                },
              ),
              onTap: () {
                _onTargetTapped(targetId);
              });
          markers[targetId] = marker;
        }
      }
    }
  }

  populateAnchors(Operation operation) async {
    if (operation.anchors != null) {
      populateBank();
      for (var anchor in operation.anchors) {
        final MarkerId markerId = MarkerId(anchor);
        final Portal portal = OperationUtils.getPortalFromID(anchor, operation);
        final Marker marker = Marker(
          markerId: markerId,
          icon: await bitmapBank.getIconFromBank(
              operation.color, context, null, null),
          position: LatLng(
            double.parse(portal.lat),
            double.parse(portal.lng),
          ),
          infoWindow: InfoWindow(
              title: portal.name,
              snippet:
                  'Links: ${OperationUtils.getLinksForPortalId(portal.id, operation).length}',
              onTap: _onAnchorInfoWindowTapped(markerId)),
          onTap: () {
            _onAnchorTapped(markerId);
          },
        );
        markers[markerId] = marker;
      }
    }
  }

  populateTeamMembers(List<Agent> agents) async {
    if (agents != null) {
      populateBank();
      for (var agent in agents) {
        if (agent.lat != null && agent.lng != null) {
          final MarkerId markerId = MarkerId("agent_${agent.name}");
          final Marker marker = Marker(
            markerId: markerId,
            icon: await bitmapBank.getIconFromBank(
                "agent_${agent.name}", context, null, null),
            position: LatLng(
              agent.lat,
              agent.lng,
            ),
            infoWindow: InfoWindow(
                title: agent.name,
                snippet: 'Last Updated: ${agent.date}',
                onTap: _onAgentInfoWindowTapped(markerId)),
            onTap: () {
              _onAgentTapped(markerId);
            },
          );
          markers[markerId] = marker;
        }
      }
    }
  }

  populateLinks(Operation operation) {
    var lineWidth = 5;
    if (Platform.isIOS) lineWidth = 2;
    if (operation.links != null) {
      populateBank();
      for (var link in operation.links) {
        final PolylineId polylineId = PolylineId(link.iD);
        final Portal fromPortal =
            OperationUtils.getPortalFromID(link.fromPortalId, operation);
        final Portal toPortal =
            OperationUtils.getPortalFromID(link.toPortalId, operation);
        final List<LatLng> points = <LatLng>[];
        points.add(
            LatLng(double.parse(fromPortal.lat), double.parse(fromPortal.lng)));
        points.add(
            LatLng(double.parse(toPortal.lat), double.parse(toPortal.lng)));
        final Polyline polyline = Polyline(
          geodesic: true,
          polylineId: polylineId,
          consumeTapEvents: true,
          color: OperationUtils.getLinkColor(this.selectedOperation),
          width: lineWidth,
          points: points,
          onTap: () {
            _onPolylineTapped(polylineId);
          },
        );
        polylines[polylineId] = polyline;
      }
    }
  }

  _onTargetInfoWindowTapped(Target target, Portal portal, MarkerId markerId) {
    //print('Tapped MarkerInfoWindow: ${markerId.value}');
    LocalStorageUtils.getGoogleId().then((googleId) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return TargetUtils.getTargetInfoAlert(
              context,
              portal,
              target,
              googleId,
              selectedOperation.iD,
              this,
              MediaQuery.of(context).size.width);
        },
      );
    });
  }

  _onTargetTapped(MarkerId targetId) {
    //print('Tapped Target: ${targetId.value}');
  }

  void _onPolylineTapped(PolylineId polylineId) {
    //print('Tapped Polyline: ${polylineId.value}');
  }

  _onAnchorInfoWindowTapped(MarkerId markerId) {
    //print('Tapped AnchorInfoWindow: ${markerId.value}');
  }

  _onAnchorTapped(MarkerId markerId) {
    //print('Tapped Marker: ${markerId.value}');
  }

  _onAgentInfoWindowTapped(MarkerId markerId) {
    //print('Tapped AgentInfoWindow: ${markerId.value}');
  }

  _onAgentTapped(MarkerId markerId) {
    //print('Tapped Agent: ${markerId.value}');
  }

  populateBank() {
    if (bitmapBank == null) bitmapBank = MapMarkerBitmapBank();
  }

  tappedOp(Op op, List<Op> operationList) async {
    await LocalStorageUtils.storeSelectedOpId(op.iD);
    setState(() {
      doRefresh(op, true);
      for (var ops in operationList) {
        if (op.iD == ops.iD)
          ops.isSelected = true;
        else
          ops.isSelected = false;
      }
    });
  }

  makeZoomedPositionFromLatLng(LatLng latLng) {
    mapController.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: latLng, zoom: ZOOMED_ZOOM_LEVEL),
    ));
  }

  makePositionFromLatLng(LatLng latLng, double zoomLevel) {
    mapController.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: latLng, zoom: zoomLevel),
    ));
  }

  setAlerFilterDropdownValue(AlertFilterType value) {
    setState(() {
      alertFilterDropdownValue = value;
    });
  }

  setAlertSortDropdownValue(AlertSortType value) {
    setState(() {
      alertSortDropdownValue = value;
    });
  }

  setLinkFilterDropdownValue(LinkFilterType value) {
    setState(() {
      linkFilterDropdownValue = value;
    });
  }

  setLinkSortDropdownValue(LinkSortType value) {
    setState(() {
      linkSortDropDownValue = value;
    });
  }

  setIsLoading() {
    setState(() {
      isLoading = true;
    });
  }

  setIsNotLoading() {
    setState(() {
      isLoading = false;
    });
  }

  pressedSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => SettingsPage(
                title: MyApp.APP_TITLE,
                useImperial: useImperialUnitsValue,
              )),
    ).then((onValue) {
      if (onValue) {
        doFullRefresh();
      }
      print('returned settings with -> $onValue');
    });
  }

  doFullRefresh() {
    Navigator.of(context).pop();
    Navigator.pushNamedAndRemoveUntil(
        context, WasabeeConstants.LOGIN_ROUTE_NAME, (r) => false);
  }
}
