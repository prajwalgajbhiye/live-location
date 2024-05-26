import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:live_location_v2/location/avtar/avtar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../consts.dart';
import '../new_login_page/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Maps Directions Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late GoogleMapController _mapController;
  final TextEditingController _emailController = TextEditingController();

  LatLng? _currentLocation;
  LatLng? _otherUserLocation;
  Set<Polyline> _polylines = {};
  double? _distance;
  late StreamSubscription<Position> _positionStreamSubscription;
  StreamSubscription<DocumentSnapshot>? _otherUserLocationSubscription;

  BitmapDescriptor? _currentUserIcon;
  BitmapDescriptor? _otherUserIcon;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _setupLocationUpdates();
    _loadSavedEmailAndFetchLocation();
    _loadSavedAvatar();
  }

  @override
  void dispose() {
    _positionStreamSubscription.cancel();
    _mapController.dispose();
    _otherUserLocationSubscription?.cancel();
    super.dispose();
  }

  // Log out method
  void logOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => LoginPage()),
          (Route<dynamic> route) => false,
    );
  }

  // Show the alert dialog
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Logout"),
          content: const Text("Are you sure you want to log out?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                logOut(context); // Perform the logout
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadCustomIcons(String avatarUrl) async {
    _currentUserIcon =
        BitmapDescriptor.fromBytes(await getBytesFromAssets(avatarUrl, 200));
  }

  Future<Uint8List> getBytesFromAssets(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetHeight: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }

  Future<void> _fetchUserLocationByEmail(String email) async {
    print("Fetching user location for email: $email");
    try {
      var locations = await _firestore
          .collection('locations')
          .where('email', isEqualTo: email)
          .get();
      if (locations.docs.isNotEmpty) {
        var userId = locations.docs.first.id;
        print("Location data: ${locations.docs.first.data()}");

        _otherUserLocationSubscription?.cancel();
        _otherUserLocationSubscription = _firestore
            .collection('locations')
            .doc(userId)
            .snapshots()
            .listen((snapshot) async {
          if (snapshot.exists) {
            var data = snapshot.data()!;
            setState(() {
              _otherUserLocation = LatLng(data['latitude'], data['longitude']);
              _updateDistance();
              _polylines.add(
                Polyline(
                  polylineId: const PolylineId("route"),
                  visible: true,
                  points: [_currentLocation!, _otherUserLocation!],
                  width: 6,
                  color: Colors.blue,
                ),
              );
              _mapController
                  .animateCamera(CameraUpdate.newLatLng(_otherUserLocation!));
            });
            // Fetch and set the avatar for the other user
            var userDoc = await _firestore.collection('users').doc(userId).get();
            if (userDoc.exists && userDoc.data() != null) {
              var avatarUrl = userDoc.data()!['avatarUrl'];
              if (avatarUrl != null) {
                _otherUserIcon = BitmapDescriptor.fromBytes(await getBytesFromAssets(avatarUrl, 200));
                setState(() {});
              }
            }
          }
        });
        _saveEmail(email);
        _saveEmailToFirestore(email); // Save email to Firestore
      } else {
        print("No location data found for the provided email.");
        _showSnackBar('No location data found for the provided email.');
      }
    } catch (e) {
      print("An error occurred while fetching user location: $e");
      _showSnackBar('An error occurred while fetching user location.');
    }
  }

  Future<void> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      print("Current position: $position");
      _updateLocationToFirestore(position.latitude, position.longitude);
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      // Fetch the avatar URL for the current user
      var user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        var userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists && userDoc.data() != null) {
          var avatarUrl = userDoc.data()!['avatarUrl'];
          if (avatarUrl != null) {
            await _loadCustomIcons(avatarUrl);
            setState(() {});
          }
        }
      }
    } else {
      print("Location permission denied");
      _showSnackBar('Location permission denied.');
    }
  }

  void _setupLocationUpdates() {
    _positionStreamSubscription =
        Geolocator.getPositionStream().listen((Position position) {
          print("Position updated: $position");
          _updateLocationToFirestore(position.latitude, position.longitude);
          setState(() {
            _currentLocation = LatLng(position.latitude, position.longitude);
            if (_otherUserLocation != null) {
              _updateDistance();
            }
          });
        });
  }

  void _updateLocationToFirestore(double latitude, double longitude) {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _firestore.collection('locations').doc(user.uid).set({
        'latitude': latitude,
        'longitude': longitude,
        'email': user.email,
        'avatarUrl': user.photoURL, // Store the avatar URL in the location
        'timestamp': FieldValue.serverTimestamp()
      });
    } else {
      print("No user logged in to update Firestore location");
    }
  }

  void _updateDistance() {
    if (_currentLocation != null && _otherUserLocation != null) {
      double distance =
      calculateDistance(_currentLocation!, _otherUserLocation!);
      print("Distance updated: $distance km");
      setState(() {
        _distance = distance;
      });
    } else {
      setState(() {
        _distance = null; // Clear distance if one location is not available
      });
    }
  }

  double calculateDistance(LatLng start, LatLng end) {
    const earthRadiusKm = 6371.0;
    double dLat = _toRadians(end.latitude - start.latitude);
    double dLon = _toRadians(end.longitude - start.longitude);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(start.latitude)) *
            cos(_toRadians(end.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double degree) => degree * pi / 180.0;

  Future<void> _setAvatar(String imageUrl) async {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'avatarUrl': imageUrl,
      });
      await _firestore.collection('locations').doc(user.uid).update({
        'avatarUrl': imageUrl,
      });
      _currentUserIcon = BitmapDescriptor.fromBytes(await getBytesFromAssets(imageUrl, 200));
      _saveAvatarToPreferences(imageUrl);
      setState(() {});
    }
  }

  Future<void> _saveAvatarToPreferences(String imageUrl) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('avatarUrl', imageUrl);
  }

  Future<void> _loadSavedAvatar() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? avatarUrl = prefs.getString('avatarUrl');
    if (avatarUrl != null) {
      await _loadCustomIcons(avatarUrl);
      setState(() {});
    }
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(child: Image.asset(imageUrl)),
              const SizedBox(height: 10),
              const Text('Set image as avatar?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _setAvatar(imageUrl);
                Navigator.of(context).pop();
              },
              child: const Text('Yes'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('No'),
            ),
          ],
        );
      },
    );
  }

  void _showEmailDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Email'),
          content: TextField(
            controller: _emailController,
            decoration: const InputDecoration(hintText: "Email"),
            keyboardType: TextInputType.emailAddress,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Submit'),
              onPressed: () {
                Navigator.of(context).pop();
                _fetchUserLocationByEmail(_emailController.text);
              },
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveEmail(String email) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('savedEmail', email);
  }

  Future<void> _saveEmailToFirestore(String email) async {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).set({
        'email': email,
      });
    }
  }

  Future<void> _loadSavedEmailAndFetchLocation() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedEmail = prefs.getString('savedEmail');
    if (savedEmail == null) {
      var user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        var userDoc = await _firestore.collection('users').doc(user.uid).get();
        savedEmail = userDoc.data()?['email'];
        if (savedEmail != null) {
          _emailController.text = savedEmail;
          _fetchUserLocationByEmail(savedEmail);
        }
      }
    } else {
      _emailController.text = savedEmail;
      _fetchUserLocationByEmail(savedEmail);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Map Page"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutDialog(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Distance: ${_distance?.toStringAsFixed(2) ?? 'Calculating...'} km',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              Expanded(
                child: GoogleMap(
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  markers: {
                    if (_currentLocation != null)
                      Marker(
                          markerId: const MarkerId('User 1'),
                          position: _currentLocation!,
                          icon: _currentUserIcon ??
                              BitmapDescriptor.defaultMarker,
                          infoWindow: const InfoWindow(title: "Your Location")),
                    if (_otherUserLocation != null)
                      Marker(
                          markerId: const MarkerId('User 2'),
                          position: _otherUserLocation!,
                          icon:
                          _otherUserIcon ?? BitmapDescriptor.defaultMarker,
                          infoWindow:
                          const InfoWindow(title: "Other User Location")),
                  },
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(20.5937, 78.9629),
                    // Coordinates for the center of India
                    zoom: 7.0,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: FloatingActionButton(
                    onPressed: _showEmailDialog,
                    tooltip: 'Enter Email',
                    child: const Icon(Icons.mail),
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(2),
                  height: 50,
                  width: 150,
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                          left: BorderSide(color: Colors.black, width: 2),
                          right: BorderSide(color: Colors.black, width: 2),
                          top: BorderSide(color: Colors.black, width: 2),
                          bottom: BorderSide(color: Colors.black, width: 2))),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      // crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Avtar(
                            onTap: () {
                              _showImageDialog(
                                  context, boy1); // Replace with your image URL
                            },
                            image: boy1),
                        Avtar(
                            onTap: () {
                              _showImageDialog(context, boy2);
                            },
                            image: boy2),
                        Avtar(
                            onTap: () {
                              _showImageDialog(context, boy3);
                            },
                            image: boy3),
                        Avtar(
                            onTap: () {
                              _showImageDialog(context, girl2);
                            },
                            image: girl2),
                        Avtar(
                            onTap: () {
                              _showImageDialog(context, boy4);
                            },
                            image: boy4),
                        Avtar(
                            onTap: () {
                              _showImageDialog(context, boy1);
                            },
                            image: boy1),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}