// import styles from './header.scss?inline'
import navbar from '../../data/navbar.json'
import { Route } from '@solidjs/router';
import styles from './NavBar.scss?inline'
import { createSignal } from 'solid-js';

export const Navbar = () => {
    // Define a state variable for the button color, with an initial color
    const [color, setColor] = createSignal("blue");

    // Define an array of colors to cycle through
    const colors = ["blue", "red", "green", "yellow", "purple"];

    // Function to change the color
    const changeColor = () => {
        // Get the current color index
        const currentColorIndex = colors.indexOf(color());
        // Calculate the next color index
        const nextColorIndex = (currentColorIndex + 1) % colors.length;
        // Set the next color
        setColor(colors[nextColorIndex]);
    };

    return (
        <>
            <style>{styles}</style>
            <div class="nav">
                <li>
                    Home
                </li>
                <li>
                    About
                </li>
                <li>
                    Projects
                </li>
            </div>
        </>
    );
};