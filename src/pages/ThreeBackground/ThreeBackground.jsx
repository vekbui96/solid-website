import { onMount, createSignal, createEffect, onCleanup } from 'solid-js';
import * as THREE from 'three';
import styles from './ThreeBackground.scss?inline'

export default function ThreeBackground() {
  let containerRef;

  onMount(() => {
    console.log(containerRef);
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x000000); 

    const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
    camera.position.z = 2;

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(window.innerWidth - 10, window.innerHeight - 10);
    containerRef.appendChild(renderer.domElement); 

    const particlesGeometry = new THREE.BufferGeometry();
    const particlesCnt = 3000;

    const posArray = new Float32Array(particlesCnt * 3); 
    for(let i = 0; i < particlesCnt * 3; i++) {
      posArray[i] = (Math.random() - 0.5) * 5; 
    }
    particlesGeometry.setAttribute('position', new THREE.BufferAttribute(posArray, 3));

    // Materials
    const particlesMaterial = new THREE.PointsMaterial({
      size: 0.005,
      color: 0xffffff,
    });

    // Particle mesh
    const particlesMesh = new THREE.Points(particlesGeometry, particlesMaterial);
    scene.add(particlesMesh);

    // Animation loop
    const animate = function () {
      requestAnimationFrame(animate);

      // Rotate the whole particle system
      particlesMesh.rotation.y += 0.001;

      renderer.render(scene, camera);
    };

    animate();

    const onResize = () => {
      renderer.setSize(window.innerWidth - 10, window.innerHeight - 10);
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
    };

    // Adjust canvas size on window resize
    window.addEventListener('resize', onResize);

    onCleanup(() => {
      window.removeEventListener('resize', onResize);
      renderer.dispose(); // Cleanup renderer resources
    });
  });



  return <div ref={containerRef} class="background" />;
}
