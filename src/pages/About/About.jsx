
import about from "../../data/about.json";
import SectionTitle from "../../components/SectionTitle";
import "./about.scss"
import heroBg from '../../images/hero-bg.jpg';

export const About = () => {
    return (
        <section className="about" id="about">
            <div className="class1">
                <div class="container2">
                    <div class="text-box">
                        <p>{about.bio}</p>
                    </div>
                    <div class="image-box">
                        <img class="image" src={heroBg}></img>
                    </div>
                </div>
            </div>
        </section>
    );
};

