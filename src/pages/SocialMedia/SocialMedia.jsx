import about from "../../data/about.json";
import * as FontAwesome from "solid-fa";
// import '../css/SocialMedia.css'

export const SocialMedia = ({className}) => {
    return (
        <div className="first">
            <h5 className="second">Share:</h5>
            <ul className="third">
                {about.socialMedia.map(media => {
                    const Icon = FontAwesome[media.icon];
                    return (
                        <li key={media.id}><a href={media.link} target="_blank" rel="noopener"><Icon/></a></li>
                    )
                })}
            </ul>
        </div>
    );
};

