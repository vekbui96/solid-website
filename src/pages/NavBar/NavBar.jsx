// import styles from './header.scss?inline'
import navbar from '../../data/navbar.json'
import { Route } from '@solidjs/router';
import styles from './NavBar.scss?inline'

export const Navbar = () => {

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
                        projecs
                    </li>
            </div>
        </>
    );
};