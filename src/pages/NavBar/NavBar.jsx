// import styles from './header.scss?inline'
import navbar from '../../data/navbar.json'
import { Route } from '@solidjs/router';
import './NavBar.scss'

const navItemActiveStyle = "before:absolute before:h-[6px] before:w-[6px] before:rounded-full before:bg-white before:left-1/2 before:-translate-x-1/2 before:-bottom-3";
const navItemHoverStyle = "after:content-[attr(data-hover)] after:absolute after:left-1/2 after:top-3/4 after:opacity-0 after:-translate-x-1/2 hover:after:top-1/2 hover:after:opacity-100 after:hover:-translate-x-1/2 after:hover:-translate-y-1/2";

export const Navbar = () => {

    return (
        <>
            <div class="nav">
                    <li>
                        Home
                    </li>
                    <li>
                        About
                    </li>
                    <li>
                        projecs
                    </li>
            </div>
        </>
    );
};