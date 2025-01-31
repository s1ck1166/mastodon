import PropTypes from 'prop-types';

import classNames from 'classnames';
import { NavLink } from 'react-router-dom';

import { Icon }  from 'mastodon/components/icon';

const ColumnLink = ({ icon, iconComponent, text, to, href, method, badge, transparent, children, ...other }) => {
  const className = classNames('column-link', { 'column-link--transparent': transparent });
  const badgeElement = typeof badge !== 'undefined' ? <span className='column-link__badge'>{badge}</span> : null;
  const iconElement = (typeof icon === 'string' || iconComponent) ? <Icon id={icon} icon={iconComponent} className='column-link__icon' /> : icon;
  const childElement = typeof children !== 'undefined' ? <p>{children}</p> : null;

  if (href) {
    return (
      <a href={href} className={className} data-method={method} title={text} {...other}>
        {iconElement}
        <span>{text}</span>
        {badgeElement}
      </a>
    );
  } else {
    return (
      <NavLink to={to} className={className} title={text} {...other}>
        {iconElement}
        <span>{text}</span>
        {badgeElement}
        {childElement}
      </NavLink>
    );
  }
};

ColumnLink.propTypes = {
  icon: PropTypes.oneOfType([PropTypes.string, PropTypes.node]).isRequired,
  iconComponent: PropTypes.func,
  text: PropTypes.string.isRequired,
  to: PropTypes.string,
  href: PropTypes.string,
  method: PropTypes.string,
  badge: PropTypes.node,
  transparent: PropTypes.bool,
  children: PropTypes.any,
};

export default ColumnLink;
