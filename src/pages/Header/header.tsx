// @ts-ignore
import styles from './header.scss?inline'
import { Navbar } from '../NavBar/NavBar';

export const Header = () => {
    return (
        <>
        <style>{styles}</style>
        <header class="topbar">
            <div class="brand">
                <span class="brand-name">Ve Bui</span>
                <span class="brand-title">Full-Stack Software Engineer</span>
            </div>
            <Navbar />
        </header>
        </>
    );
};
