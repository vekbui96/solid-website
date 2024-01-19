import './header.scss'
import { Navbar } from '../NavBar/NavBar';

export const Header = () => {

    return (
        <>
            <header className="header">
                <div className="container">
                    <div className="subHeader">
                        <div className="flex items-center justify-between">
                            <span className="sm:hidden">
                            </span>
                        </div>
                        <Navbar/>
                    </div>
                </div>
            </header>
        </>
    );
};