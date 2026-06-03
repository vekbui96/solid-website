// @ts-ignore
import styles from './header.scss?inline'
import { Navbar } from '../NavBar/NavBar';
import { useGlobalContext } from '../../context/GlobalContext';

export const Header = () => {
    const ctx = useGlobalContext();
    const toTop = () => {
        const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
        window.scrollTo({ top: 0, behavior: reduce ? "auto" : "smooth" });
    };

    return (
        <>
        <style>{styles}</style>
        <header class="topbar" classList={{ "topbar-dark": ctx?.onDark() }}>
            <button class="brand" onClick={toTop}>
                <span class="brand-name">Ve Bui</span>
                <span class="brand-title">Full-Stack Software Engineer</span>
            </button>
            <Navbar />
        </header>
        </>
    );
};
