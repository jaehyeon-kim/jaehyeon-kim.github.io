(()=>{var e={fallback:"https://jaehyeon.me/",homes:{en:"https://jaehyeon.me/"}};(()=>{let o=navigator.language||navigator.userLanguage;if(o in e.homes){window.location.href=e.homes[o];return}let n=o.split("-");for(let a in e.homes)if(a.indexOf(n[0])===0){window.location.href=e.homes[a];return}window.location.href=e.fallback})();})();
