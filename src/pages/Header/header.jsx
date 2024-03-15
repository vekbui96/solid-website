import styles from './header.scss?inline'
import { Navbar } from '../NavBar/NavBar';

export const Header = () => {

    return (
        <>
        <style>{styles}</style>
            <div class="header-container">
                <div class="header-details">
                    <h1>
                        Ve Bui
                    </h1>
                    <p>
                        Software Engineer
                    </p>
                </div>
                <Navbar />
            </div>
        </>
    );
};