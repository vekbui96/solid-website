// import styles from './header.scss?inline'
import navbar from '../../data/navbar.json'
import { checkExternalLink } from '../../utils/checkExternalLink';
import { Route } from '@solidjs/router';
import './navbar.scss'

const navItemActiveStyle = "before:absolute before:h-[6px] before:w-[6px] before:rounded-full before:bg-white before:left-1/2 before:-translate-x-1/2 before:-bottom-3";
const navItemHoverStyle = "after:content-[attr(data-hover)] after:absolute after:left-1/2 after:top-3/4 after:opacity-0 after:-translate-x-1/2 hover:after:top-1/2 hover:after:opacity-100 after:hover:-translate-x-1/2 after:hover:-translate-y-1/2";

export const Navbar = () => {

    return (
        <>
 <nav className="ect">
                  <ul className="boxes" >
                      {navbar.map(item => (
                          <li key={item.id}>
                              {
                            //   checkExternalLink(item.href)
                                item.href ? (
                                  <a
                                      href={item.href} target="_blank"
                                      data-hover={item.name.toLowerCase()}
                                      className={`block text-white font-medium text-sm relative cursor-pointer after:duration-300 ${navItemHoverStyle}`}
                                  >
                                      <span className="item">{item.name}</span>
                                  </a>
                              ) : 
                              
                              (
                                  <Route
                                      spy={true}
                                      smooth={true}
                                      to={item.href}
                                      activeClass={navItemActiveStyle}
                                      data-hover={item.name.toLowerCase()}
                                      className={`block text-white font-medium text-sm relative cursor-pointer after:duration-300 ${navItemHoverStyle}`}
                                  >
                                      <span className="item">{item.name}</span>
                                  </Route>
                              )}
                          </li>
                      ))}
                  </ul>
              </nav>
        </>
    );
};