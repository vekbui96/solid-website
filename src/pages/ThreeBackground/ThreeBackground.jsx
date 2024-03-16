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
    camera.position.z = 3;

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(window.innerWidth - 10, window.innerHeight - 10);
    containerRef.appendChild(renderer.domElement);

    let geometry = new THREE.SphereGeometry(1, 32, 32);
    let material = new THREE.MeshBasicMaterial({
      color: 0xAAAAAA, // Light grey for monochromatic theme
      wireframe: true,
    });
    const sphere = new THREE.Mesh(geometry, material);
    scene.add(sphere);

    // Point light
    const pointLight = new THREE.PointLight(0xFFFFFF, 1, 100);
    pointLight.position.set(5, 5, 5);
    scene.add(pointLight);

    // Ambient light
    const ambientLight = new THREE.AmbientLight(0x404040); // Soft white light
    scene.add(ambientLight);

    // Plane (ground)
    const planeGeometry = new THREE.PlaneGeometry(5, 5);
    const planeMaterial = new THREE.ShadowMaterial({ opacity: 0.5 });
    const plane = new THREE.Mesh(planeGeometry, planeMaterial);
    plane.rotation.x = -Math.PI / 2; // Rotate the plane to be horizontal
    plane.position.y = -1.5;
    plane.receiveShadow = true; // Enable the plane to receive shadows
    scene.add(plane);

    // Spotlight setup
    const spotlight = new THREE.SpotLight(0xffffff, 1);
    spotlight.position.set(2, 3, 3);
    spotlight.castShadow = true; // Enable the spotlight to cast shadows
    scene.add(spotlight);

    // Spotlight target
    const targetObject = new THREE.Object3D();
    scene.add(targetObject);
    spotlight.target = targetObject;

    const particlesGeometry = new THREE.BufferGeometry();
    const particlesCnt = 7000;

    const posArray = new Float32Array(particlesCnt * 5);
    for (let i = 0; i < particlesCnt * 3; i++) {
      posArray[i] = (Math.random() - 0.5) * 5;
    }
    particlesGeometry.setAttribute('position', new THREE.BufferAttribute(posArray, 3));

    // Materials
    const particlesMaterial = new THREE.PointsMaterial({
      size: 0.003,
      color: 0xffffff
    });

    // Particle mesh
    const particlesMesh = new THREE.Points(particlesGeometry, particlesMaterial);
    scene.add(particlesMesh);


    // Animation loop
    function animate() {
      requestAnimationFrame(animate);

      // Rotate the sphere for a dynamic effect
      // sphere.rotation.x += 0.001;
      sphere.rotation.y += 0.0008;

      // Rotate the whole particle system
      particlesMesh.rotation.y += 0.0001;

      // Move the spotlight in a circle

      renderer.render(scene, camera);
    }

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
