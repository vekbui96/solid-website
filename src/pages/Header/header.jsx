import styles from './header.scss?inline'
import { Navbar } from '../NavBar/NavBar';

export const Header = () => {

    return (
        <>
            <style>{styles}</style>
            <header className="header">
                Ve Bui
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