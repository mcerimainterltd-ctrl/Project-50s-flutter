  @override
  Widget build(BuildContext context) {
    final item = widget.items[_current];
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F), // Cinematic Deep Black
      body: Stack(
        children: [
          // 1. MAIN IMAGE VIEW
          GestureDetector(
            onTap: () => setState(() => _showInfo = !_showInfo),
            child: PageView.builder(
              controller: _page,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: widget.items[i].url,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      // Clear placeholder to ensure no white flash/veil
                      placeholder: (c, u) => const Center(
                        child: CircularProgressIndicator(color: Colors.white24)
                      ),
                      errorWidget: (c, u, e) => const Icon(Icons.error, color: Colors.white24),
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. CINEMATIC OVERLAY (Controls & Info)
          if (_showInfo) ...[
            Positioned(
              top: 0, left: 0, right: 0,
              child: _buildCinematicHeader(context),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildCinematicFooter(item),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCinematicHeader(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.7), Colors.transparent],
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            Text('${_current + 1} / ${widget.items.length}', 
                 style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCinematicFooter(GalleryItem item) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(20),
          color: Colors.black.withOpacity(0.4),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.mode.toUpperCase(), 
                     style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(item.description ?? 'No description', 
                     style: const TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
