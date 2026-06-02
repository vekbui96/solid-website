import { For } from 'solid-js';
// @ts-ignore
import styles from './NavBar.scss?inline'
import { useGlobalContext } from '../../context/GlobalContext'

const links = [
    { id: "home", label: "Home" },
    { id: "experience", label: "Experience" },
    { id: "about", label: "About" },
    { id: "projects", label: "Projects" },
] as const;

export const Navbar = () => {
    const context = useGlobalContext();

    return (
        <>
            <style>{styles}</style>
            <nav class="nav">
                <For each={links}>
                    {(link) => (
                        <button
                            class="nav-link"
                            classList={{ active: context?.page() === link.id }}
                            onClick={() => context?.setPage(link.id)}
                        >
                            {link.label}
                        </button>
                    )}
                </For>
            </nav>
        </>
    );
};
