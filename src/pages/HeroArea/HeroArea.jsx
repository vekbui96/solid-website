
import './HeroArea.scss';
import { createSignal, Show, createEffect, onMount, onCleanup } from 'solid-js';
import { PerspectiveCamera, Scene, WebGLRenderer, BoxGeometry, MeshBasicMaterial, Mesh } from 'three';

// function Cube() {
//     const [rotationX, setRotationX] = createSignal(0);
//     const [rotationY, setRotationY] = createSignal(0);
  
//     createEffect(() => {
//       setRotationX(rotationX() + 0.01);
//       setRotationY(rotationY() + 0.01);
//     });
  
//     return (
//       <Mesh rotation-x={rotationX()} rotation-y={rotationY()}>
//         <BoxGeometry args={[1, 1, 1]} />
//         <MeshBasicMaterial color="blue" />
//       </Mesh>
//     );
//   }

// function App() {
//     const renderer = new WebGLRenderer({ antialias: true });
//     renderer.setSize(window.innerWidth, window.innerHeight);
//     document.body.appendChild(renderer.domElement);
  
//     const scene = new Scene();
//     const camera = new PerspectiveCamera(70, window.innerWidth / window.innerHeight, 0.1, 100);
//     camera.position.z = 4;
  
//     function animate() {
//       requestAnimationFrame(animate);
//       renderer.render(scene, camera);
//     };
  
//     // Function to handle window resizing
//     function onWindowResize() {
//       camera.aspect = window.innerWidth / window.innerHeight;
//       camera.updateProjectionMatrix();
//       renderer.setSize(window.innerWidth, window.innerHeight);
//     }
  
//     // Add event listener on component mount
//     onMount(() => {
//       window.addEventListener('resize', onWindowResize);
//       onWindowResize(); // Initial resize call
//     });
  
//     // Cleanup on unmount
//     onCleanup(() => {
//       window.removeEventListener('resize', onWindowResize);
//     });
  
//     animate();
  
//     return (
//       <Show when={renderer}>
//         <scene>
//           <Cube />
//         </scene>
//       </Show>
//     );
//   }

export const HeroArea = () => {

    // const renderer = new WebGLRenderer({ antialias: true });
    // renderer.setSize(window.innerWidth, window.innerHeight);
    // document.body.appendChild(renderer.domElement);
  
    // const scene = new Scene();
    // const camera = new PerspectiveCamera(70, window.innerWidth / window.innerHeight, 0.1, 100);
    // camera.position.z = 4;
  
    // function animate() {
    //   requestAnimationFrame(animate);
    //   renderer.render(scene, camera);
    // };
  
    // animate();

    return (
    <>
    {/* {App()} */}
    </>
    );
};
