import { onCleanup, onMount } from 'solid-js';
import * as THREE from 'three';

export default function ThreeBackground() {
  let containerRef;

  onMount(() => {
        const scene = new THREE.Scene();
        const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
        const renderer = new THREE.WebGLRenderer();
        renderer.setSize(window.innerWidth, window.innerHeight);
        containerRef.appendChild(renderer.domElement); // You might want to append this to a specific element instead
    
        // Add a cube
        const geometry = new THREE.BoxGeometry();
        const material = new THREE.MeshBasicMaterial({ color: 0xE5E5E5 });
        const cube = new THREE.Mesh(geometry, material);
        scene.add(cube);
    
        camera.position.z = 5;
    
        // Animation loop
        const animate = function () {
          requestAnimationFrame(animate);
    
          cube.rotation.x += 0.01;
          cube.rotation.y += 0.01;
    
          renderer.render(scene, camera);
        };
    
        animate();
    
        // Adjust canvas size on window resize
        window.addEventListener('resize', () => {
          renderer.setSize(window.innerWidth, window.innerHeight);
          camera.aspect = window.innerWidth / window.innerHeight;
          camera.updateProjectionMatrix();
        });
  });

  return <div ref={containerRef}></div>;
}
