
import about from "../../data/about.json";
import SectionTitle from "../../components/SectionTitle";
import "./about.scss"

export const About = () => {
    return (
        <section className="about" id="about">
            <div className="class1">
                <div className="col-start-6 col-end-13">
                    <div className="bio mt-5 sm:mt-10 md:mt-0">
                        <div class="container2">
                            <div class="text-box">
                                <SectionTitle
                                    title="About Me"
                                    className="hidden lg:block"
                                />
                                <p>{about.bio}</p>
                            </div>
                            <div class="image-box">
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>
    );
};

