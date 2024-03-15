import './header.scss'
import { Navbar } from '../NavBar/NavBar';

export const Header = () => {

    return (
        <>
            <div class="header-container">
                <h1>
                    Ve Bui
                </h1>
                <p>
                    name
                </p>
                <div class="todo-remove-spacing"></div>
                <Navbar/>
            </div>
        </>
    );
};