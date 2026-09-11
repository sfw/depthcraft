// Depthcraft Demo Kit: Three.js v0
// Minimal Three.js wrapper for offline demos
// Sandboxed execution environment with no external fetches

// Define a global DepthcraftKit namespace
window.DepthcraftKit = {
  version: '0.1.0',
  THREE: null,
  
  // Initialize kit (called by demo entry scripts)
  init: async function() {
    if (this.THREE) return this.THREE;
    
    // Import Three.js from bundled module
    const THREE = await import('./three.module.min.js');
    this.THREE = THREE;
    return THREE;
  },
  
  // Helper: create a basic scene setup
  createScene: function(containerEl) {
    if (!this.THREE) {
      throw new Error('DepthcraftKit not initialized. Call await DepthcraftKit.init() first.');
    }
    
    const THREE = this.THREE;
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(75, containerEl.clientWidth / containerEl.clientHeight, 0.1, 1000);
    
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(containerEl.clientWidth, containerEl.clientHeight);
    renderer.setPixelRatio(window.devicePixelRatio);
    containerEl.appendChild(renderer.domElement);
    
    return { scene, camera, renderer };
  },
  
  // Helper: window resize handler
  onWindowResize: function(camera, renderer) {
    const container = renderer.domElement.parentElement;
    if (!container) return;
    
    camera.aspect = container.clientWidth / container.clientHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(container.clientWidth, container.clientHeight);
  }
};
