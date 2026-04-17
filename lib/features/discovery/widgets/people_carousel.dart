import 'package:flutter/material.dart';

class PeoplePerspectiveCarousel extends StatefulWidget {
  final List<Map<String, String>> users;

  const PeoplePerspectiveCarousel({Key? key, required this.users}) : super(key: key);

  @override
  State<PeoplePerspectiveCarousel> createState() => _PeoplePerspectiveCarouselState();
}

class _PeoplePerspectiveCarouselState extends State<PeoplePerspectiveCarousel> {
  late PageController _pageController;
  double _currentPage = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.7);
    _pageController.addListener(() {
      setState(() {
        _currentPage = _pageController.page!;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.users.length,
        itemBuilder: (context, index) {
          // Calculate the distance from the center for the 3D tilt
          double relativePosition = index - _currentPage;
          
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002) // Perspective depth
              ..rotateY(relativePosition * 0.4), // Tilt effect
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundImage: NetworkImage(widget.users[index]['avatar']!),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.users[index]['name']!,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    "${widget.users[index]['mutuals']} mutuals",
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: const Text("Add", style: TextStyle(fontSize: 12)),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
