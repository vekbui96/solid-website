// import styles from './header.scss?inline'
import navbar from '../../data/navbar.json'
import { Route } from '@solidjs/router';
import styles from './NavBar.scss?inline'
import { createEffect, createSignal } from 'solid-js';
import { useGlobalContext } from '../../context/GlobalContext'

export const Navbar = () => {
    // Define a state variable for the button color, with an initial color
    const context = useGlobalContext();

    const setPage = (page : string) => {
        context.setPage(page);
    }

    return (
        <>
            <style>{styles}</style>
            <div class="nav">
                <li onClick={() => (setPage("home"))}>
                    Home
                </li>
                <li onClick={() => (setPage("about"))}>
                    About
                </li>
                <li onClick={() => (setPage("projects"))}>
                    Projects
                </li>
            </div>
        </>
    );
};