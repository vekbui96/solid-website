import './header.scss'
import { Navbar } from '../NavBar/NavBar';

export const Header = () => {

    return (
        <>
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