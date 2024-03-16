// import styles from './header.scss?inline'

// @ts-ignore
import styles from './header.scss?inline'
import { Navbar } from '../NavBar/NavBar';

export const Header = () => {

    return (
        <>
        <style>{styles}</style>
            <div class="header-container">
                <div class="header-details left-line">
                    <h1>
                        Ve Bui ff
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